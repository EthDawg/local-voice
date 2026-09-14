import Foundation
@preconcurrency import CloudKit
#if os(macOS)
import Security
#endif

extension PhotoCloudConfiguration {
    /// iOS does not publicly expose SecTask. Its opt-in build marker must be set
    /// only by a packaging path that verifies the signed profile/entitlements.
    public static func current(bundle: Bundle = .main) -> Self {
        let container = bundle.object(forInfoDictionaryKey: "WorkbenchPhotoCloudContainer") as? String ?? "iCloud.com.ethdawg.workbench.preview"
        let environment = bundle.object(forInfoDictionaryKey: "WorkbenchPhotoCloudEnvironment") as? String ?? ""
        let provisioned = acceptsProvisionedMarker(bundle.object(forInfoDictionaryKey: "WorkbenchPhotoCloudProvisioned"))
        let missing = "Private iCloud photo handoff needs a provisioned Workbench build. Photos can still be saved locally."
        guard provisioned, container.hasPrefix("iCloud."), container.count <= 200,
              ["Development", "Production"].contains(environment) else {
            return Self(isConfigured: false, container: container, environment: environment, explanation: missing)
        }
        #if os(macOS)
        guard let task = SecTaskCreateFromSelf(nil),
              let services = SecTaskCopyValueForEntitlement(task, "com.apple.developer.icloud-services" as CFString, nil) as? [String],
              services.contains("CloudKit"),
              let containers = SecTaskCopyValueForEntitlement(task, "com.apple.developer.icloud-container-identifiers" as CFString, nil) as? [String],
              containers.contains(container),
              let signedEnvironment = SecTaskCopyValueForEntitlement(task, "com.apple.developer.icloud-container-environment" as CFString, nil) as? String,
              signedEnvironment == environment,
              let team = SecTaskCopyValueForEntitlement(task, "com.apple.developer.team-identifier" as CFString, nil) as? String,
              !team.isEmpty else {
            return Self(isConfigured: false, container: container, environment: environment, explanation: missing)
        }
        #endif
        return Self(isConfigured: true, container: container, environment: environment,
                    explanation: "Private iCloud photo handoff is available in this build.")
    }
    static func acceptsProvisionedMarker(_ value: Any?) -> Bool {
        if let string = value as? String { return ["YES", "true", "1"].contains(string) }
        guard let number = value as? NSNumber, CFGetTypeID(number) == CFBooleanGetTypeID() else { return false }
        return number.boolValue
    }
}

@MainActor final class CloudPhotoTransport: PhotoHandoffTransport {
    let configuration: PhotoCloudConfiguration
    var onAccountChange: (@MainActor @Sendable () -> Void)?
    private var cloud: CKContainer?
    private var operations: [UUID: CKOperation] = [:]
    private var replies: [UUID: @Sendable () -> Void] = [:]
    private var generation = UUID()
    private var observer: CloudObservation?
    private static let zoneName = "WorkbenchPhotosV1"
    init(configuration: PhotoCloudConfiguration = .current()) {
        self.configuration = configuration
        if configuration.isConfigured {
            let token = NotificationCenter.default.addObserver(forName: .CKAccountChanged, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.cancel(); self?.onAccountChange?() }
            }
            observer = CloudObservation(token)
        }
    }
    private func container() throws -> CKContainer {
        guard configuration.isConfigured else { throw PhotoHandoffError.unavailable(configuration.explanation) }
        if let cloud { return cloud }
        let value = CKContainer(identifier: configuration.container)
        cloud = value; return value
    }
    func cancel() {
        generation = UUID()
        for finish in replies.values { finish() }
        replies.removeAll()
        for operation in operations.values { operation.cancel() }
        operations.removeAll()
    }
    func identity() async throws -> PhotoAccount {
        let token = generation
        let cloud = try container()
        let status: CKAccountStatus = try await response(timeout: 30) { reply in
            cloud.accountStatus { status, error in
                if let error { reply.finish(.failure(error)) } else { reply.finish(.success(status)) }
            }
        }
        guard token == generation else { throw PhotoHandoffError.accountChanged }
        guard status == .available else { throw PhotoHandoffError.unavailable("Sign in to iCloud and allow Workbench access before sending. Your local photos are kept.") }
        let id: CKRecord.ID = try await response(timeout: 30) { reply in
            cloud.fetchUserRecordID { id, error in
                if let error { reply.finish(.failure(error)) }
                else if let id { reply.finish(.success(id)) }
                else { reply.finish(.failure(PhotoHandoffError.accountChanged)) }
            }
        }
        guard token == generation else { throw PhotoHandoffError.accountChanged }
        let account = PhotoAccount(container: configuration.container, environment: configuration.environment, userRecordName: id.recordName)
        try account.validate(); return account
    }
    private func verify(_ account: PhotoAccount) async throws {
        try account.validate()
        let token = generation
        guard try await identity() == account, generation == token, !Task.isCancelled else { throw PhotoHandoffError.accountChanged }
    }
    private func zone(_ account: PhotoAccount) -> CKRecordZone.ID {
        // Outgoing operations retain their captured owner, even if the signed-in
        // account changes. CloudKit's response alias is handled only on receipt.
        CKRecordZone.ID(zoneName: Self.zoneName, ownerName: account.userRecordName)
    }
    private func recordID(_ id: UUID, account: PhotoAccount) -> CKRecord.ID {
        CKRecord.ID(recordName: id.uuidString, zoneID: zone(account))
    }
    private func ensureZone(_ account: PhotoAccount) async throws {
        try await verify(account)
        let operation = CKModifyRecordZonesOperation(recordZonesToSave: [CKRecordZone(zoneID: zone(account))], recordZoneIDsToDelete: nil)
        let _: Void = try await perform(operation) { reply in
            operation.modifyRecordZonesResultBlock = { reply.finish($0) }
        }
        try await verify(account)
    }
    func upload(_ photo: RemoteHandoffPhoto, fileURL: URL, account: PhotoAccount) async throws {
        _ = try photo.validated()
        try PhotoMedia.validate(PhotoHandoffStore.read(fileURL, limit: PhotoMedia.maximumTransferBytes), against: photo)
        try await ensureZone(account)
        let record = CKRecord(recordType: "PhotoV1", recordID: recordID(photo.id, account: account))
        record["metadata"] = try JSONEncoder().encode(photo) as CKRecordValue
        record["image"] = CKAsset(fileURL: fileURL)
        let operation = CKModifyRecordsOperation(recordsToSave: [record], recordIDsToDelete: nil)
        operation.savePolicy = .ifServerRecordUnchanged; operation.isAtomic = true
        let acceptedDuplicate = CloudLocked(false)
        do {
            let _: Void = try await perform(operation) { reply in
                operation.perRecordSaveBlock = { _, result in
                    if case .failure(let error) = result, let cloudError = error as? CKError,
                       cloudError.code == .serverRecordChanged, let server = cloudError.serverRecord,
                       let existing = try? Self.decode(server, account: account), existing == photo {
                        acceptedDuplicate.update { $0 = true }
                    }
                }
                operation.modifyRecordsResultBlock = { result in
                    if acceptedDuplicate.value { reply.finish(.success(())) } else { reply.finish(result) }
                }
            }
        } catch { throw Self.map(error) }
        try await verify(account)
    }
    func changes(after checkpoint: Data?, account: PhotoAccount) async throws -> PhotoChangePage {
        try await verify(account)
        let settings = CKFetchRecordZoneChangesOperation.ZoneConfiguration()
        if let checkpoint {
            guard checkpoint.count <= 512_000 else { throw PhotoHandoffError.expiredCheckpoint }
            do { settings.previousServerChangeToken = try NSKeyedUnarchiver.unarchivedObject(ofClass: CKServerChangeToken.self, from: checkpoint) }
            catch { throw PhotoHandoffError.expiredCheckpoint }
        }
        settings.resultsLimit = 10; settings.desiredKeys = ["metadata"]
        let zoneID = zone(account)
        let operation = CKFetchRecordZoneChangesOperation(recordZoneIDs: [zoneID], configurationsByRecordZoneID: [zoneID: settings])
        operation.fetchAllChanges = false
        let batch = CloudLocked(CloudBatch())
        let page: PhotoChangePage
        do {
            page = try await perform(operation) { reply in
                operation.recordWasChangedBlock = { _, result in
                    do {
                        let photo = try Self.decode(result.get(), account: account)
                        batch.update {
                            if $0.photos.count < 20 { $0.photos.append(photo) }
                            else { $0.failure = PhotoHandoffError.invalid("iCloud returned too many photos in one batch.") }
                        }
                    } catch { batch.update { $0.failure = error } }
                }
                operation.recordWithIDWasDeletedBlock = { id, type in
                    do {
                        let uuid = try Self.deletedPhotoID(id, recordType: type, account: account)
                        batch.update {
                            if $0.deleted.count < 100 { $0.deleted.append(uuid) }
                            else { $0.failure = PhotoHandoffError.invalid("iCloud returned too many removals in one batch.") }
                        }
                    } catch { batch.update { $0.failure = error } }
                }
                operation.recordZoneFetchResultBlock = { _, result in
                    do {
                        let value = try result.get()
                        let data = try NSKeyedArchiver.archivedData(withRootObject: value.serverChangeToken, requiringSecureCoding: true)
                        batch.update { $0.checkpoint = data; $0.hasMore = value.moreComing }
                    } catch { batch.update { $0.failure = error } }
                }
                operation.fetchRecordZoneChangesResultBlock = { result in
                    let value = batch.value
                    if let error = value.failure { reply.finish(.failure(error)) }
                    else if case .failure(let error) = result { reply.finish(.failure(error)) }
                    else { reply.finish(.success(PhotoChangePage(photos: value.photos, deletedIDs: value.deleted,
                                                               checkpoint: value.checkpoint, hasMore: value.hasMore))) }
                }
            }
        } catch let error as CKError where error.code == .zoneNotFound {
            try await verify(account); return PhotoChangePage(photos: [])
        } catch { throw Self.map(error) }
        try await verify(account); return page
    }
    func download(_ photo: RemoteHandoffPhoto, account: PhotoAccount) async throws -> Data {
        _ = try photo.validated(); try await verify(account)
        let operation = CKFetchRecordsOperation(recordIDs: [recordID(photo.id, account: account)])
        let received = CloudLocked<Result<Data, Error>?>(nil)
        let data: Data = try await perform(operation) { reply in
            operation.perRecordResultBlock = { _, result in
                do {
                    let record = try result.get()
                    guard try Self.decode(record, account: account) == photo,
                          let asset = record["image"] as? CKAsset, let url = asset.fileURL else {
                        throw PhotoHandoffError.invalid("The iCloud photo changed or its image is unavailable.")
                    }
                    let bytes = try PhotoHandoffStore.read(url, limit: PhotoMedia.maximumTransferBytes)
                    try PhotoMedia.validate(bytes, against: photo)
                    received.update { $0 = .success(bytes) }
                } catch { received.update { $0 = .failure(error) } }
            }
            operation.fetchRecordsResultBlock = { result in
                if case .failure(let error) = result { reply.finish(.failure(error)) }
                else { reply.finish(received.value ?? .failure(PhotoHandoffError.invalid("iCloud did not provide the requested photo."))) }
            }
        }
        try await verify(account); return data
    }
    func remove(_ id: UUID, account: PhotoAccount) async throws {
        try await verify(account)
        let requestedID = recordID(id, account: account)
        let operation = CKModifyRecordsOperation(recordsToSave: nil, recordIDsToDelete: [requestedID])
        let _: Void = try await perform(operation) { reply in
            operation.modifyRecordsResultBlock = { result in
                if case .failure(let error) = result, Self.isAlreadyRemoved(error, recordID: requestedID) {
                    reply.finish(.success(()))
                } else { reply.finish(result) }
            }
        }
        try await verify(account)
    }
    nonisolated static func isAlreadyRemoved(_ error: Error, recordID: CKRecord.ID) -> Bool {
        guard let cloud = error as? CKError else { return false }
        if cloud.code == .unknownItem || cloud.code == .zoneNotFound { return true }
        // CloudKit can wrap the single-record result in partialFailure. Only
        // accept a missing result for the exact record this operation deleted.
        guard cloud.code == .partialFailure, let failures = cloud.partialErrorsByItemID,
              failures.count == 1, let nested = failures[recordID] as? CKError else { return false }
        return nested.code == .unknownItem || nested.code == .zoneNotFound
    }
    /// Accept the SDK's current-user alias only for a response from this adapter's
    /// private database. Callers verify the captured real account before and after
    /// each operation; the alias never becomes a stored identity or outgoing owner.
    private nonisolated static func isResponseZone(_ zoneID: CKRecordZone.ID, account: PhotoAccount) -> Bool {
        zoneID.zoneName == "WorkbenchPhotosV1" &&
            (zoneID.ownerName == account.userRecordName || zoneID.ownerName == CKCurrentUserDefaultName)
    }
    nonisolated static func deletedPhotoID(_ id: CKRecord.ID, recordType: String, account: PhotoAccount) throws -> UUID {
        try account.validate()
        guard recordType == "PhotoV1", isResponseZone(id.zoneID, account: account),
              let uuid = UUID(uuidString: id.recordName) else {
            throw PhotoHandoffError.invalid("An unsupported iCloud photo record was removed.")
        }
        return uuid
    }
    nonisolated static func decode(_ record: CKRecord, account: PhotoAccount) throws -> RemoteHandoffPhoto {
        try account.validate()
        guard record.recordType == "PhotoV1", isResponseZone(record.recordID.zoneID, account: account),
              let data = record["metadata"] as? Data, data.count <= 16_000 else {
            throw PhotoHandoffError.invalid("An iCloud photo record has an unsupported format or owner.")
        }
        let photo = try JSONDecoder().decode(RemoteHandoffPhoto.self, from: data).validated()
        guard UUID(uuidString: record.recordID.recordName) == photo.id else { throw PhotoHandoffError.invalid("An iCloud photo ID does not match its metadata.") }
        return photo
    }
    private func perform<T: Sendable>(_ operation: CKDatabaseOperation, configure: (CloudReply<T>) -> Void) async throws -> T {
        let database = try container().privateCloudDatabase
        let id = UUID(); operations[id] = operation
        defer { operations.removeValue(forKey: id); replies.removeValue(forKey: id) }
        operation.configuration.timeoutIntervalForRequest = 30
        operation.configuration.timeoutIntervalForResource = 120
        let reply = CloudReply<T>(cancel: { operation.cancel() })
        replies[id] = { reply.finish(.failure(PhotoHandoffError.cancelled)) }
        configure(reply)
        do { return try await reply.wait(timeout: 125) { database.add(operation) } }
        catch { throw Self.map(error) }
    }
    private func response<T: Sendable>(timeout: TimeInterval, start: (CloudReply<T>) -> Void) async throws -> T {
        let reply = CloudReply<T>()
        let id = UUID(); replies[id] = { reply.finish(.failure(PhotoHandoffError.cancelled)) }
        defer { replies.removeValue(forKey: id) }
        return try await reply.wait(timeout: timeout) { start(reply) }
    }
    private nonisolated static func map(_ error: Error) -> Error {
        guard let cloud = error as? CKError else { return error }
        if cloud.code == .changeTokenExpired { return PhotoHandoffError.expiredCheckpoint }
        if cloud.code == .notAuthenticated || cloud.code == .permissionFailure { return PhotoHandoffError.accountChanged }
        if let seconds = cloud.retryAfterSeconds, seconds.isFinite, seconds > 0 {
            return PhotoHandoffError.retryAfter(Date().addingTimeInterval(min(seconds, 86_400)), "iCloud is temporarily busy. The photo stays queued; try again later.")
        }
        return cloud
    }
}

private final class CloudObservation: @unchecked Sendable {
    let token: NSObjectProtocol
    init(_ token: NSObjectProtocol) { self.token = token }
    deinit { NotificationCenter.default.removeObserver(token) }
}

private struct CloudBatch {
    var photos: [RemoteHandoffPhoto] = []
    var deleted: [UUID] = []
    var checkpoint: Data?
    var hasMore = false
    var failure: Error?
}
/// CloudKit callbacks can use different queues. All shared callback state is locked.
private final class CloudLocked<T>: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: T
    init(_ value: T) { stored = value }
    var value: T { lock.lock(); defer { lock.unlock() }; return stored }
    func update(_ mutate: (inout T) -> Void) { lock.lock(); defer { lock.unlock() }; mutate(&stored) }
}
/// A deadline/cancellation resumes once even if CloudKit later calls its completion.
private final class CloudReply<T: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<T, Error>?
    private var result: Result<T, Error>?
    private var cancel: (@Sendable () -> Void)?
    private var timer: DispatchWorkItem?
    init(cancel: (@Sendable () -> Void)? = nil) { self.cancel = cancel }
    func finish(_ value: Result<T, Error>) {
        lock.lock()
        guard result == nil else { lock.unlock(); return }
        result = value; let pending = continuation; continuation = nil
        let cancellation = cancel; cancel = nil; timer?.cancel(); timer = nil
        lock.unlock()
        if case .failure = value { cancellation?() }
        pending?.resume(with: value)
    }
    @MainActor func wait(timeout: TimeInterval, start: () -> Void) async throws -> T {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { pending in
                lock.lock()
                if let result { lock.unlock(); pending.resume(with: result); return }
                continuation = pending
                let timeoutWork = DispatchWorkItem { [weak self] in self?.finish(.failure(PhotoHandoffError.timeout)) }
                timer = timeoutWork
                lock.unlock()
                DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + timeout, execute: timeoutWork)
                start()
            }
        } onCancel: { self.finish(.failure(PhotoHandoffError.cancelled)) }
    }
}
