import Foundation
@preconcurrency import CloudKit

/// Explicit foreground CKSyncEngine cycles. No engine/container exists in an
/// unsigned default build, and no background subscription is claimed here.
@MainActor public final class CloudSceneSync: SceneSyncTransport {
    public var onAccountChange: (@MainActor @Sendable () -> Void)?
    private let configuration: SceneCloudConfiguration
    private var cloud: CKContainer?
    private var cycle: SceneEngineCycle?
    private var observer: SceneCloudObservation?
    private var generation = UUID()
    private var identityReplies: [UUID: @Sendable () -> Void] = [:]
    public init(configuration: SceneCloudConfiguration) {
        self.configuration = configuration
        if configuration.isConfigured {
            observer = SceneCloudObservation(NotificationCenter.default.addObserver(forName: .CKAccountChanged, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.cancel(); self?.onAccountChange?() }
            })
        }
    }
    public func cancel() {
        generation = UUID(); cycle?.stop(SceneSyncError.cancelled)
        for reply in identityReplies.values { reply() }; identityReplies.removeAll()
    }
    private func container() throws -> CKContainer {
        guard configuration.isConfigured else { throw SceneSyncError.unavailable }
        if let cloud { return cloud }
        let value = CKContainer(identifier: configuration.container); cloud = value; return value
    }
    public func currentAccount() async throws -> SceneSyncAccount {
        let token = generation; let cloud = try container()
        let status: CKAccountStatus = try await identityResponse { reply in
            cloud.accountStatus { status, error in
                if let error { reply.finish(.failure(error)) } else { reply.finish(.success(status)) }
            }
        }
        guard token == generation, !Task.isCancelled else { throw SceneSyncError.accountChanged }
        guard status == .available else { throw SceneSyncError.unavailable }
        let id: CKRecord.ID = try await identityResponse { reply in
            cloud.fetchUserRecordID { id, error in
                if let error { reply.finish(.failure(error)) }
                else if let id { reply.finish(.success(id)) }
                else { reply.finish(.failure(SceneSyncError.accountChanged)) }
            }
        }
        guard token == generation, !Task.isCancelled else { throw SceneSyncError.accountChanged }
        let account = SceneSyncAccount(container: configuration.container, environment: configuration.environment, userRecordName: id.recordName)
        try account.validate(); return account
    }
    private func identityResponse<T: Sendable>(_ start: (SceneCloudReply<T>) -> Void) async throws -> T {
        let id = UUID(); let reply = SceneCloudReply<T>()
        identityReplies[id] = { reply.finish(.failure(SceneSyncError.cancelled)) }
        defer { identityReplies[id] = nil }
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                reply.install(continuation); start(reply)
                Task { try? await Task.sleep(for: .seconds(30)); reply.finish(.failure(SceneSyncError.unavailable)) }
            }
        } onCancel: { reply.finish(.failure(SceneSyncError.cancelled)) }
    }
    public func synchronize(account: SceneSyncAccount, state: Data?, uploads: [SceneSyncUpload],
                            onEvent: @escaping @MainActor @Sendable (SceneSyncEvent) throws -> Void) async throws {
        guard cycle == nil else { throw SceneSyncError.cancelled }
        let token = generation
        guard try await currentAccount() == account, token == generation else { throw SceneSyncError.accountChanged }
        let value = try SceneEngineCycle(database: container().privateCloudDatabase, account: account, state: state,
                                        uploads: uploads, onEvent: onEvent)
        cycle = value
        defer { if cycle === value { cycle = nil }; value.cleanup() }
        try await withTaskCancellationHandler {
            try await value.run { [weak self] in
                guard let self, token == self.generation, try await self.currentAccount() == account else { throw SceneSyncError.accountChanged }
            }
        } onCancel: { Task { @MainActor in value.stop(SceneSyncError.cancelled) } }
        guard token == generation else { throw SceneSyncError.accountChanged }
    }
}

/// Small revision envelope; all authored content and images live in the one bounded package asset.
struct SceneCloudMetadata: Codable, Equatable, Sendable {
    var version = 1
    var id: UUID
    var revision: UUID
    var modified: Date
    var isDeleted: Bool
    var conflictOf: UUID?
    var account: SceneSyncAccount
    init(_ record: SavedSceneRecord, account: SceneSyncAccount) {
        id = record.id; revision = record.revision; modified = record.modified
        isDeleted = record.isDeleted; conflictOf = record.conflictOf; self.account = account
    }
    func validate(account: SceneSyncAccount) throws {
        try account.validate()
        guard version == 1, self.account == account, modified.timeIntervalSince1970.isFinite else { throw SceneSyncError.invalidEnvelope }
    }
    static func validateID(_ id: CKRecord.ID, account: SceneSyncAccount) throws {
        // CKCurrentUserDefaultName is a documented response alias, accepted only
        // inside this current, identity-verified private database operation.
        guard id.zoneID.zoneName == "WorkbenchScenesV1",
              [account.userRecordName, CKCurrentUserDefaultName].contains(id.zoneID.ownerName),
              let uuid = UUID(uuidString: id.recordName), uuid.uuidString == id.recordName else { throw SceneSyncError.invalidEnvelope }
    }
    static func decode(_ record: CKRecord, account: SceneSyncAccount) throws -> SceneCloudMetadata {
        try Self.validateID(record.recordID, account: account)
        guard record.recordType == "SceneV1", let bytes = record["metadata"] as? Data, bytes.count <= 4096 else { throw SceneSyncError.invalidEnvelope }
        let value = try JSONDecoder().decode(SceneCloudMetadata.self, from: bytes); try value.validate(account: account)
        guard value.id.uuidString == record.recordID.recordName else { throw SceneSyncError.invalidEnvelope }; return value
    }

}

@MainActor private final class SceneEngineCycle: CKSyncEngineDelegate {
    static let zoneName = "WorkbenchScenesV1"
    static let recordType = "SceneV1"
    let account: SceneSyncAccount
    private let database: CKDatabase
    private let savedState: CKSyncEngine.State.Serialization?
    private let onEvent: @MainActor @Sendable (SceneSyncEvent) throws -> Void
    private var zoneEstablished: Bool
    private var latestSerialization: CKSyncEngine.State.Serialization?
    private let directory: URL
    private var engine: CKSyncEngine?
    private var failure: Error?
    private var outgoing: [CKRecord.ID: CKRecord] = [:]
    private var snapshots: [UUID: SceneSyncUpload] = [:]
    private var submitted = Set<CKRecord.ID>()
    private var fetched = Set<CKRecord.ID>()
    private var receivedCount = 0
    private var receivedBytes = 0
    private var zoneID: CKRecordZone.ID { CKRecordZone.ID(zoneName: Self.zoneName, ownerName: account.userRecordName) }

    init(database: CKDatabase, account: SceneSyncAccount, state: Data?, uploads: [SceneSyncUpload],
         onEvent: @escaping @MainActor @Sendable (SceneSyncEvent) throws -> Void) throws {
        try account.validate(); self.account = account; self.database = database; self.onEvent = onEvent
        guard database.databaseScope == .private, uploads.count <= 12, (state?.count ?? 0) <= 8_000_000 else { throw SceneSyncError.invalidEnvelope }
        let checkpoint = try state.map { try JSONDecoder().decode(SceneEngineCheckpoint.self, from: $0) }
        guard checkpoint == nil || (checkpoint?.version == 1 && checkpoint?.account == account) else { throw SceneSyncError.invalidEnvelope }
        savedState = checkpoint?.serialization; latestSerialization = checkpoint?.serialization
        zoneEstablished = checkpoint?.zoneEstablished ?? false
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("workbench-scene-sync-" + UUID().uuidString, isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
            var total = 0
            for upload in uploads {
                let record = upload.record
                guard record.account == account, record.scene == upload.package.scene, snapshots[record.id] == nil else { throw SceneSyncError.invalidEnvelope }
                let bytes = try upload.package.encoded(); total += bytes.count
                guard total <= 120_000_000 else { throw SceneSyncError.invalidEnvelope }
                let file = directory.appendingPathComponent(record.id.uuidString + ".workbench-scene")
                try bytes.write(to: file, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
                let cloudRecord: CKRecord
                if let fields = record.remoteSystemFields {
                    guard fields.count <= 100_000 else { throw SceneSyncError.invalidEnvelope }
                    let decoder = try NSKeyedUnarchiver(forReadingFrom: fields); decoder.requiresSecureCoding = true
                    defer { decoder.finishDecoding() }
                    guard let restored = CKRecord(coder: decoder) else { throw SceneSyncError.invalidEnvelope }
                    try SceneCloudMetadata.validateID(restored.recordID, account: account)
                    guard restored.recordType == Self.recordType, restored.recordID.recordName == record.id.uuidString else { throw SceneSyncError.invalidEnvelope }
                    cloudRecord = restored
                } else { cloudRecord = CKRecord(recordType: Self.recordType, recordID: CKRecord.ID(recordName: record.id.uuidString, zoneID: zoneID)) }
                cloudRecord["metadata"] = try JSONEncoder().encode(SceneCloudMetadata(record, account: account)) as CKRecordValue
                cloudRecord["packageAsset"] = CKAsset(fileURL: file)
                outgoing[cloudRecord.recordID] = cloudRecord; snapshots[record.id] = upload
            }
        } catch { try? FileManager.default.removeItem(at: directory); throw error }
    }
    func cleanup() { try? FileManager.default.removeItem(at: directory) }
    func stop(_ error: Error) {
        if failure == nil { failure = error }
        if let engine { Task { await engine.cancelOperations() } }
    }
    private func check() throws { if let failure { throw failure }; if Task.isCancelled { throw SceneSyncError.cancelled } }
    func run(verifyAccount: @escaping @MainActor () async throws -> Void) async throws {
        var configuration = CKSyncEngine.Configuration(database: database, stateSerialization: savedState, delegate: self)
        configuration.automaticallySync = false
        let engine = CKSyncEngine(configuration); self.engine = engine
        defer { self.engine = nil }
        // Reconstruct outbound pending changes from the durable local dirty revisions,
        // not an engine checkpoint that could predate a local commit.
        for change in engine.state.pendingRecordZoneChanges { engine.state.remove(pendingRecordZoneChanges: [change]) }
        for change in engine.state.pendingDatabaseChanges { engine.state.remove(pendingDatabaseChanges: [change]) }
        if !zoneEstablished { engine.state.add(pendingDatabaseChanges: [.saveZone(CKRecordZone(zoneID: zoneID))]) }
        let group = CKOperationGroup(); group.defaultConfiguration = CKOperation.Configuration()
        group.defaultConfiguration.timeoutIntervalForRequest = 30; group.defaultConfiguration.timeoutIntervalForResource = 120
        // Establish the private zone before its first fetch. No records are queued at this point.
        try await verifyAccount(); try check()
        if !zoneEstablished { try await engine.sendChanges(.init(scope: .zoneIDs([zoneID]), operationGroup: group)); try check() }
        try await verifyAccount(); try check()
        try await engine.fetchChanges(.init(scope: .zoneIDs([zoneID]), operationGroup: group)); try check()
        // A fetched ID is deferred to the next foreground cycle so a stale snapshot
        // cannot re-send a revision superseded by that fetch/merge.
        let changes = outgoing.keys.filter { id in !fetched.contains(where: { $0.recordName == id.recordName }) }.map { CKSyncEngine.PendingRecordZoneChange.saveRecord($0) }
        engine.state.add(pendingRecordZoneChanges: changes)
        try await verifyAccount(); try check()
        if !changes.isEmpty {
            // Cached system fields may use CloudKit's documented owner alias.
            // Record-ID scope includes those exact validated records, never another zone.
            try await engine.sendChanges(.init(scope: .recordIDs(Array(outgoing.keys)), operationGroup: group)); try check()
        }
    }
    func nextFetchChangesOptions(_ context: CKSyncEngine.FetchChangesContext, syncEngine: CKSyncEngine) async -> CKSyncEngine.FetchChangesOptions {
        var options = context.options; options.scope = .zoneIDs([zoneID]); return options
    }
    func nextRecordZoneChangeBatch(_ context: CKSyncEngine.SendChangesContext, syncEngine: CKSyncEngine) async -> CKSyncEngine.RecordZoneChangeBatch? {
        guard failure == nil, self.engine === syncEngine else { return nil }
        var records: [CKRecord] = []
        for change in syncEngine.state.pendingRecordZoneChanges where context.options.scope.contains(change) {
            guard case .saveRecord(let id) = change, !submitted.contains(id), let record = outgoing[id] else { continue }
            records.append(record); submitted.insert(id)
            if records.count >= 2 { break } // CKAsset bytes remain bounded even for large scenes.
        }
        return records.isEmpty ? nil : .init(recordsToSave: records, atomicByZone: false)
    }
    func handleEvent(_ event: CKSyncEngine.Event, syncEngine: CKSyncEngine) async {
        guard failure == nil, self.engine === syncEngine else { return }
        do {
            switch event {
            case .stateUpdate(let event):
                latestSerialization = event.stateSerialization
                try persistCheckpoint()
            case .accountChange(let event):
                // An initial sign-in event for the already verified identity is harmless.
                switch event.changeType {
                case .signIn(let user) where user.recordName == account.userRecordName: break
                default: throw SceneSyncError.accountChanged
                }
            case .fetchedDatabaseChanges(let event):
                if event.deletions.contains(where: { $0.zoneID.zoneName == Self.zoneName }) { throw SceneSyncError.removedRemotely }
            case .fetchedRecordZoneChanges(let event):
                guard event.deletions.isEmpty else { throw SceneSyncError.removedRemotely }
                for change in event.modifications {
                    let (record, package) = try decode(change.record)
                    try onEvent(.received(record, package))
                    // A known base is safe to send against in this same cycle.
                    // Only a different server revision supersedes our captured upload.
                    if snapshots[record.id]?.record.baseRevision != record.revision { fetched.insert(change.record.recordID) }
                }
            case .sentRecordZoneChanges(let event):
                guard event.deletedRecordIDs.isEmpty, event.failedRecordDeletes.isEmpty else { throw SceneSyncError.invalidEnvelope }
                for saved in event.savedRecords {
                    let metadata = try SceneCloudMetadata.decode(saved, account: account)
                    guard let upload = snapshots[metadata.id], SceneCloudMetadata(upload.record, account: account) == metadata else { throw SceneSyncError.invalidEnvelope }
                    var record = upload.record; record.remoteSystemFields = try Self.systemFields(saved)
                    try onEvent(.acknowledged(record))
                }
                for failed in event.failedRecordSaves {
                    if failed.error.code == .serverRecordChanged, let server = failed.error.serverRecord {
                        // The server conflict may omit CKAsset bytes. Fetch the complete
                        // server record in the next cycle; never manufacture a partial scene.
                        if let asset = server["packageAsset"] as? CKAsset, asset.fileURL != nil {
                            let (record, package) = try decode(server); try onEvent(.received(record, package))
                        } else { throw failed.error }
                    } else { throw failed.error }
                }
            case .sentDatabaseChanges(let event):
                if let failed = event.failedZoneSaves.first { throw failed.error }
                guard event.deletedZoneIDs.isEmpty, event.failedZoneDeletes.isEmpty else { throw SceneSyncError.invalidEnvelope }
                for zone in event.savedZones {
                    guard zone.zoneID.zoneName == Self.zoneName,
                          [account.userRecordName, CKCurrentUserDefaultName].contains(zone.zoneID.ownerName) else { throw SceneSyncError.invalidEnvelope }
                    zoneEstablished = true
                }
                try persistCheckpoint()
            case .didFetchRecordZoneChanges(let event): if let error = event.error { throw error }
            default: break
            }
        } catch {
            // Event handlers cannot throw to CKSyncEngine. Latch first failure and
            // cancel without awaiting inside its delegate callback (avoids deadlock).
            stop(error)
        }
    }
    private func persistCheckpoint() throws {
        guard let latestSerialization else { return }
        let checkpoint = SceneEngineCheckpoint(account: account, zoneEstablished: zoneEstablished, serialization: latestSerialization)
        try onEvent(.checkpoint(JSONEncoder().encode(checkpoint)))
    }
    private func decode(_ record: CKRecord) throws -> (SavedSceneRecord, ScenePackage) {
        let metadata = try SceneCloudMetadata.decode(record, account: account)
        guard let url = (record["packageAsset"] as? CKAsset)?.fileURL else { throw SceneSyncError.invalidEnvelope }
        let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
        guard values.isRegularFile == true, values.isSymbolicLink != true,
              let size = values.fileSize, size > 0, size <= ScenePackage.maximumBytes else { throw SceneSyncError.invalidEnvelope }
        receivedCount += 1; receivedBytes += size
        guard receivedCount <= 128, receivedBytes <= 240_000_000 else { throw SceneDocumentError.invalid("More scenes are waiting in iCloud. Refresh again to continue.") }
        let package = try ScenePackage.decode(Data(contentsOf: url))
        guard package.scene.id == metadata.id else { throw SceneSyncError.invalidEnvelope }
        var saved = SavedSceneRecord(scene: package.scene, revision: metadata.revision, modified: metadata.modified)
        saved.account = account; saved.isDeleted = metadata.isDeleted; saved.conflictOf = metadata.conflictOf
        saved.baseRevision = metadata.revision; saved.remoteSystemFields = try Self.systemFields(record)
        return (saved, package)
    }
    private static func systemFields(_ record: CKRecord) throws -> Data {
        let coder = NSKeyedArchiver(requiringSecureCoding: true); record.encodeSystemFields(with: coder); coder.finishEncoding()
        guard coder.encodedData.count <= 100_000 else { throw SceneSyncError.invalidEnvelope }; return coder.encodedData
    }
}

private struct SceneEngineCheckpoint: Codable {
    var version = 1
    var account: SceneSyncAccount
    var zoneEstablished: Bool
    var serialization: CKSyncEngine.State.Serialization
}

private final class SceneCloudObservation {
    let token: NSObjectProtocol
    init(_ token: NSObjectProtocol) { self.token = token }
    deinit { NotificationCenter.default.removeObserver(token) }
}
private final class SceneCloudReply<T: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<T, Error>?
    private var result: Result<T, Error>?
    func install(_ continuation: CheckedContinuation<T, Error>) {
        lock.lock()
        if let result { lock.unlock(); continuation.resume(with: result) }
        else { self.continuation = continuation; lock.unlock() }
    }
    func finish(_ result: Result<T, Error>) {
        lock.lock(); guard self.result == nil else { lock.unlock(); return }
        self.result = result; let continuation = continuation; self.continuation = nil
        lock.unlock(); continuation?.resume(with: result)
    }
}
