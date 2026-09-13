import Foundation

public struct SceneSyncAccount: Codable, Equatable, Sendable {
    public var container: String
    public var environment: String
    public var userRecordName: String
    public init(container: String, environment: String, userRecordName: String) {
        self.container = container; self.environment = environment; self.userRecordName = userRecordName
    }
    public func validate() throws {
        guard container.hasPrefix("iCloud."), container.count <= 200,
              ["Development", "Production"].contains(environment),
              !userRecordName.isEmpty, userRecordName.count <= 255,
              !["__defaultOwner__", "_defaultOwner"].contains(userRecordName),
              userRecordName.unicodeScalars.allSatisfy({ $0.isASCII && !CharacterSet.controlCharacters.contains($0) })
        else { throw SceneDocumentError.invalid("Your iCloud account could not be identified safely.") }
    }
}

public struct SavedSceneRecord: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID { scene.id }
    public var scene: PortableScene
    public var revision: UUID
    public var baseRevision: UUID?
    public var account: SceneSyncAccount?
    public var remoteSystemFields: Data?
    public var modified: Date
    public var isDeleted: Bool
    public var conflictOf: UUID?
    public var isDirty: Bool { revision != baseRevision }
    public init(scene: PortableScene, revision: UUID = UUID(), modified: Date = Date()) {
        self.scene = scene; self.revision = revision; self.modified = modified; isDeleted = false
    }
}

public struct SceneLibraryArchive: Codable, Equatable, Sendable {
    public var format = "workbench-scene-library"
    public var version = 1
    public var records: [SavedSceneRecord] = []
    public var account: SceneSyncAccount?
    public var syncEnabled = false
    public var engineState: Data?
    /// Source IDs make a repeated, interrupted migration idempotent.
    public var adoptedLegacyIDs: [String] = []
    public init() {}
    public func validated() throws -> Self {
        guard format == "workbench-scene-library", version == 1 else { throw SceneDocumentError.futureVersion }
        guard records.count <= 1000, Set(records.map(\.id)).count == records.count,
              adoptedLegacyIDs.count <= 2000, adoptedLegacyIDs.allSatisfy({ $0.count <= 240 }),
              (engineState?.count ?? 0) <= 8_000_000, !syncEnabled || account != nil else {
            throw SceneDocumentError.invalid("This scene library is outside the supported limits. Its original has been kept.")
        }
        try account?.validate()
        for record in records {
            _ = try record.scene.validated(); try record.account?.validate()
            guard record.modified.timeIntervalSince1970.isFinite,
                  (record.remoteSystemFields?.count ?? 0) <= 100_000,
                  record.account != nil || (record.baseRevision == nil && record.remoteSystemFields == nil)
            else { throw SceneDocumentError.invalid("A saved scene has inconsistent sync state.") }
        }
        return self
    }
}

/// One local manifest is authoritative. Assets are immutable and written before
/// the manifest. An interrupted write can leave an unused file, never a live
/// reference to half an image. Cleanup is deliberately a separate operation.
public final class SceneLibraryStore {
    public let directory: URL
    public var manifest: URL { directory.appendingPathComponent("scene-library.json") }
    public var assetsDirectory: URL { directory.appendingPathComponent("Assets", isDirectory: true) }
    public static let maximumManifestBytes = 24_000_000
    private var expectedBytes: Data?
    private var loaded = false
    public init(directory: URL) { self.directory = directory }

    public func load() throws -> SceneLibraryArchive {
        let bytes = try readManifest()
        let value = try bytes.map { try JSONDecoder().decode(SceneLibraryArchive.self, from: $0).validated() } ?? SceneLibraryArchive()
        expectedBytes = bytes; loaded = true
        return value
    }
    private func readManifest() throws -> Data? {
        try checkDirectory(directory)
        try rejectSymbolicLink(manifest)
        guard FileManager.default.fileExists(atPath: manifest.path) else { return nil }
        let values = try manifest.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey, .isSymbolicLinkKey])
        guard values.isRegularFile == true, values.isSymbolicLink != true,
              (values.fileSize ?? Int.max) <= Self.maximumManifestBytes else { throw SceneDocumentError.storageBlocked }
        return try Data(contentsOf: manifest)
    }
    public func save(_ archive: SceneLibraryArchive) throws {
        guard loaded else { throw SceneDocumentError.storageBlocked }
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        let bytes = try encoder.encode(archive.validated())
        guard bytes.count <= Self.maximumManifestBytes else { throw SceneDocumentError.invalid("The scene library is full. Export work before adding more scenes.") }
        guard try readManifest() == expectedBytes else { throw SceneDocumentError.concurrentChange }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try bytes.write(to: manifest, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        expectedBytes = bytes
    }
    public func assetURL(_ name: String) throws -> URL {
        guard SceneAsset.isName(name) else { throw SceneDocumentError.missingAsset }
        try checkAssetsDirectory()
        return assetsDirectory.appendingPathComponent(name)
    }
    private func checkAssetsDirectory() throws {
        // The file can be ordinary while its parent redirects reads/writes.
        // Inspect links even when their destination has disappeared.
        for url in [directory, assetsDirectory] { try checkDirectory(url) }
    }
    private func rejectSymbolicLink(_ url: URL) throws {
        if let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
           attributes[.type] as? FileAttributeType == .typeSymbolicLink { throw SceneDocumentError.storageBlocked }
    }
    private func checkDirectory(_ url: URL) throws {
        try rejectSymbolicLink(url)
        if let values = try? url.resourceValues(forKeys: [.isDirectoryKey]), values.isDirectory != true {
            throw SceneDocumentError.storageBlocked
        }
    }
    public func asset(_ name: String) throws -> Data {
        let url = try assetURL(name)
        let values = try url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey, .isSymbolicLinkKey])
        guard values.isRegularFile == true, values.isSymbolicLink != true,
              (values.fileSize ?? Int.max) <= SceneAsset.maximumBytes else { throw SceneDocumentError.missingAsset }
        let bytes = try Data(contentsOf: url); try SceneAsset.validate(bytes, named: name)
        return bytes
    }
    @discardableResult public func importAsset(_ data: Data) throws -> String {
        let name = SceneAsset.name(for: data); try SceneAsset.validate(data, named: name)
        let url = try assetURL(name)
        try rejectSymbolicLink(url)
        if FileManager.default.fileExists(atPath: url.path) {
            guard try asset(name) == data else { throw SceneDocumentError.missingAsset }
            return name
        }
        try FileManager.default.createDirectory(at: assetsDirectory, withIntermediateDirectories: true)
        try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        return name
    }
    public func package(for scene: PortableScene) throws -> ScenePackage {
        var assets: [String: Data] = [:]
        for name in scene.assets { assets[name] = try asset(name) }
        return try ScenePackage(scene: scene, assets: assets).validated()
    }
    public func installAssets(from package: ScenePackage) throws {
        _ = try package.validated()
        for data in package.assets.values { _ = try importAsset(data) }
    }
}

/// Merge complete revisions, preserving both authors' work on a conflict. Dates
/// are display metadata; device clocks never decide which authored values win.
public enum SceneRevisionMerge {
    public static func receive(_ remote: SavedSceneRecord, into archive: inout SceneLibraryArchive,
                               account: SceneSyncAccount, conflictID: UUID = UUID()) throws {
        var next = archive
        try apply(remote, into: &next, account: account, conflictID: conflictID)
        archive = try next.validated()
    }
    private static func apply(_ remote: SavedSceneRecord, into archive: inout SceneLibraryArchive,
                              account: SceneSyncAccount, conflictID: UUID) throws {
        try account.validate(); _ = try remote.scene.validated()
        guard remote.account == account else { throw SceneDocumentError.invalid("This scene belongs to a different iCloud account.") }
        var accepted = remote; accepted.baseRevision = remote.revision
        guard let index = archive.records.firstIndex(where: { $0.id == remote.id }) else {
            archive.records.append(accepted); return
        }
        let local = archive.records[index]
        guard local.account == nil || local.account == account else {
            throw SceneDocumentError.invalid("A scene from another account has the same identifier. Both local libraries are kept.")
        }
        if local.revision == remote.revision {
            // A matching revision must also match its authored content.
            guard local.scene == remote.scene, local.isDeleted == remote.isDeleted else {
                throw SceneDocumentError.invalid("An iCloud scene reused a revision with different contents.")
            }
            archive.records[index].account = account
            archive.records[index].baseRevision = remote.revision
            archive.records[index].remoteSystemFields = remote.remoteSystemFields
            return
        }
        if local.isDirty {
            if local.baseRevision == remote.revision {
                // Fetching our known base must not erase a newer local edit.
                archive.records[index].remoteSystemFields = remote.remoteSystemFields
                return
            }
            // A dirty deletion also needs review if another device edited the scene.
            // Preserve the local version as an ordinary editable copy.
            guard !archive.records.contains(where: { $0.id == conflictID }) else {
                throw SceneDocumentError.invalid("The conflict copy needs a new identifier. Both original revisions are kept.")
            }
            var copy = local
            copy.scene.id = conflictID
            copy.scene.name = String(local.scene.name.prefix(140)) + " · kept copy"
            copy.revision = UUID(); copy.baseRevision = nil; copy.remoteSystemFields = nil
            copy.isDeleted = false; copy.conflictOf = local.id; copy.account = account
            archive.records.append(copy)
        }
        archive.records[index] = accepted
    }
}
