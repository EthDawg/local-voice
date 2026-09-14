import XCTest
import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
@testable import SceneSyncKit

final class SceneDocumentTests: XCTestCase {
    private let ownerA = SceneSyncAccount(container: "iCloud.com.ethdawg.workbench.preview",
        environment: "Production", userRecordName: "_synthetic_owner_a")
    private let ownerB = SceneSyncAccount(container: "iCloud.com.ethdawg.workbench.preview",
        environment: "Production", userRecordName: "_synthetic_owner_b")

    private func directory() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("SceneDocumentTests-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        return root
    }

    private func image(seed: Int = 10) throws -> Data {
        let context = try XCTUnwrap(CGContext(data: nil, width: 4, height: 3, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(red: CGFloat(seed) / 255, green: 0.4, blue: 0.8, alpha: 0.7))
        context.fill(CGRect(x: 0, y: 0, width: 4, height: 3))
        context.setFillColor(CGColor(gray: 1, alpha: 1)); context.fill(CGRect(x: 0, y: 2, width: 1, height: 1))
        let data = NSMutableData()
        let destination = try XCTUnwrap(CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, try XCTUnwrap(context.makeImage()), nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        return data as Data
    }

    private func fixture() throws -> ScenePackage {
        let images = try [10, 50, 90, 130, 170].map { try image(seed: $0) }
        let names = images.map(SceneAsset.name)
        var scene = PortableScene(name: "Synthetic prepared scene", background: names[0])
        scene.backgroundX = 0.23; scene.backgroundY = 0.79; scene.zoom = 1.8
        scene.phoneX = 0.17; scene.phoneY = 0.64; scene.phoneHeight = 0.81
        scene.viewport = SceneDevice(aspect: 0.6, border: 0.02, corners: 0.17)
        scene.logo = SceneLogoLayer(image: names[1], corner: "bottomLeft", width: 0.22, backing: "dark")
        scene.hand = SceneHandLayer(image: names[2], scale: 1.4, x: -0.3, y: 0.2, mirrored: true, tone: "deeper")
        scene.persona = ScenePersonaLayer(image: names[3], x: 0.8, y: 0.9, width: 0.24)
        scene.persona?.card = SceneCardStyle(portrait: names[4], label: "Site coordinator", red: 0.13, green: 0.5, blue: 0.87)
        scene.groupID = UUID()
        scene.legacyMobileProject = Data("{\"caption\":\"Synthetic original composition\"}".utf8)
        return ScenePackage(scene: scene, assets: Dictionary(uniqueKeysWithValues: zip(names, images)))
    }

    private func archive(_ records: [SavedSceneRecord] = []) -> SceneLibraryArchive {
        var value = SceneLibraryArchive(); value.records = records; return value
    }

    private func syncedRecord() throws -> SavedSceneRecord {
        var record = SavedSceneRecord(scene: try fixture().scene, modified: Date(timeIntervalSince1970: 100))
        record.account = ownerA; record.baseRevision = record.revision; record.remoteSystemFields = Data([1])
        return record
    }

    func testPortablePackageRoundTripPreservesEveryAuthoredLayerAndSourceBytes() throws {
        let original = try fixture()
        XCTAssertEqual(original.scene.assets.count, 5)
        let bytes = try original.encoded()
        XCTAssertEqual(bytes.prefix(8), Data("bplist00".utf8))
        let reopened = try ScenePackage.decode(bytes)
        XCTAssertEqual(reopened, original)
        XCTAssertEqual(reopened.scene.persona?.card?.label, "Site coordinator")
        XCTAssertEqual(reopened.scene.persona?.card?.red, 0.13)
        XCTAssertEqual(reopened.scene.hand?.mirrored, true)
        XCTAssertEqual(reopened.scene.legacyMobileProject, original.scene.legacyMobileProject)
        for (name, data) in reopened.assets {
            XCTAssertEqual(data, original.assets[name])
            let source = try XCTUnwrap(CGImageSourceCreateWithData(data as CFData, nil))
            let image = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
            XCTAssertEqual(image.width, 4); XCTAssertEqual(image.height, 3)
        }
    }

    func testHashNamesRejectTraversalAndContentSubstitution() throws {
        XCTAssertEqual(SceneAsset.digest(Data("abc".utf8)), "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
        let bytes = try image(), name = SceneAsset.name(for: bytes)
        XCTAssertTrue(SceneAsset.isName(name)); XCTAssertNoThrow(try SceneAsset.validate(bytes, named: name))
        for invalid in ["../" + name, "/" + name, name.uppercased(), String(name.dropFirst()), name + ".png", "", "a.image"] {
            XCTAssertFalse(SceneAsset.isName(invalid))
            XCTAssertThrowsError(try SceneAsset.validate(bytes, named: invalid))
        }
        XCTAssertThrowsError(try SceneAsset.validate(image(seed: 20), named: name))
        XCTAssertThrowsError(try SceneAsset.validate(Data(), named: name))
        let text = Data("This is not an image.".utf8)
        XCTAssertThrowsError(try SceneAsset.validate(text, named: SceneAsset.name(for: text)))
    }

    func testHeaderOnlyPNGIsNotAcceptedAsUsableImage() throws {
        let bytes = try image()
        // Preserve the signature, full IHDR and IEND but remove pixel chunks.
        let headerOnly = Data(bytes.prefix(33)) + Data(bytes.suffix(12))
        let source = try XCTUnwrap(CGImageSourceCreateWithData(headerOnly as CFData, nil))
        XCTAssertNotNil(CGImageSourceCopyPropertiesAtIndex(source, 0, nil))
        XCTAssertNil(CGImageSourceCreateImageAtIndex(source, 0, nil))
        XCTAssertThrowsError(try SceneAsset.validate(headerOnly, named: SceneAsset.name(for: headerOnly)))
    }

    func testPackagesRejectMissingExtraWrongVersionAndBadLayerValues() throws {
        let good = try fixture()
        var missing = good; missing.assets.removeValue(forKey: good.scene.background)
        XCTAssertThrowsError(try missing.validated())
        var extra = good; let extraBytes = try image(seed: 250); extra.assets[SceneAsset.name(for: extraBytes)] = extraBytes
        XCTAssertThrowsError(try extra.validated())
        var future = good; future.version = 999
        XCTAssertThrowsError(try future.validated())
        let encoder = PropertyListEncoder(); encoder.outputFormat = .binary
        XCTAssertThrowsError(try ScenePackage.decode(encoder.encode(future)))
        for mutate: (inout PortableScene) -> Void in [
            { $0.backgroundX = .nan }, { $0.backgroundY = .infinity }, { $0.zoom = 0.99 },
            { $0.phoneHeight = 1.1 }, { $0.viewport?.aspect = 0 },
            { $0.logo?.corner = "middle" }, { $0.logo?.width = .nan },
            { $0.hand?.scale = .infinity }, { $0.hand?.tone = "invented" },
            { $0.persona?.width = 0 }, { $0.persona?.card?.red = .nan },
            { $0.persona?.card?.label = "Private\ncontrol" },
            { $0.persona?.card?.label = String(repeating: "x", count: 81) },
            { $0.name = " \n " }, { $0.background = "../photo.png" }
        ] {
            var bad = good.scene; mutate(&bad)
            XCTAssertThrowsError(try bad.validated())
        }
    }

    func testStorageRoundTripKeepsSourceFilesAndImportsIdempotently() throws {
        let root = try directory(), package = try fixture()
        let source = root.appendingPathComponent("picked.png")
        try XCTUnwrap(package.assets[package.scene.background]).write(to: source)
        let store = SceneLibraryStore(directory: root.appendingPathComponent("Library"))
        var value = try store.load()
        try store.installAssets(from: package)
        try store.installAssets(from: package)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: store.assetsDirectory.path).count, 5)
        value.records = [SavedSceneRecord(scene: package.scene, modified: Date(timeIntervalSince1970: 100))]
        value.adoptedLegacyIDs = ["legacy-test-fixture"]
        try store.save(value)
        XCTAssertEqual(try Data(contentsOf: source), package.assets[package.scene.background])
        try FileManager.default.removeItem(at: source)
        let reopened = SceneLibraryStore(directory: store.directory)
        XCTAssertEqual(try reopened.load(), value)
        XCTAssertEqual(try reopened.package(for: value.records[0].scene), package)
    }

    func testOversizedSparseFilesAreRejectedBeforeUse() throws {
        let root = try directory(), store = SceneLibraryStore(directory: root)
        try FileManager.default.createDirectory(at: store.assetsDirectory, withIntermediateDirectories: true)
        let name = SceneAsset.name(for: try image()), url = try store.assetURL(name)
        XCTAssertTrue(FileManager.default.createFile(atPath: url.path, contents: Data()))
        let asset = try FileHandle(forWritingTo: url)
        try asset.truncate(atOffset: UInt64(SceneAsset.maximumBytes + 1)); try asset.close()
        XCTAssertThrowsError(try store.asset(name))
        XCTAssertEqual(try url.resourceValues(forKeys: [.fileSizeKey]).fileSize, SceneAsset.maximumBytes + 1)
        XCTAssertTrue(FileManager.default.createFile(atPath: store.manifest.path, contents: Data()))
        let manifest = try FileHandle(forWritingTo: store.manifest)
        try manifest.truncate(atOffset: UInt64(SceneLibraryStore.maximumManifestBytes + 1)); try manifest.close()
        XCTAssertThrowsError(try store.load())
        XCTAssertThrowsError(try store.save(SceneLibraryArchive()))
        XCTAssertEqual(try store.manifest.resourceValues(forKeys: [.fileSizeKey]).fileSize, SceneLibraryStore.maximumManifestBytes + 1)
    }

    func testConcurrentWritersAndNewManifestPreventStaleSave() throws {
        let root = try directory(), first = SceneLibraryStore(directory: root), second = SceneLibraryStore(directory: root)
        var old = try first.load(), current = try second.load()
        let package = try fixture(); try second.installAssets(from: package)
        current.records = [SavedSceneRecord(scene: package.scene)]
        try second.save(current)
        let committed = try Data(contentsOf: second.manifest)
        old.adoptedLegacyIDs = ["stale writer"]
        XCTAssertThrowsError(try first.save(old)) { XCTAssertEqual($0 as? SceneDocumentError, .concurrentChange) }
        XCTAssertEqual(try Data(contentsOf: second.manifest), committed)
        var reopened = try first.load(); reopened.records[0].scene.name = "Reopened deliberately"
        try first.save(reopened)
        XCTAssertThrowsError(try second.save(current))
        XCTAssertEqual(try SceneLibraryStore(directory: root).load(), reopened)
    }

    func testCorruptFutureAndSymlinkManifestsPreserveOriginalBytes() throws {
        for bytes in [Data("{bad JSON".utf8), Data("{\"format\":\"workbench-scene-library\",\"version\":999,\"records\":[],\"syncEnabled\":false,\"adoptedLegacyIDs\":[]}".utf8)] {
            let root = try directory(), store = SceneLibraryStore(directory: root)
            try bytes.write(to: store.manifest)
            XCTAssertThrowsError(try store.load())
            XCTAssertThrowsError(try store.save(SceneLibraryArchive()))
            XCTAssertEqual(try Data(contentsOf: store.manifest), bytes)
        }
        let root = try directory(), outside = root.appendingPathComponent("outside.json")
        let bytes = try JSONEncoder().encode(SceneLibraryArchive()); try bytes.write(to: outside)
        let store = SceneLibraryStore(directory: root.appendingPathComponent("Library"))
        try FileManager.default.createDirectory(at: store.directory, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: store.manifest, withDestinationURL: outside)
        XCTAssertThrowsError(try store.load())
        XCTAssertThrowsError(try store.save(SceneLibraryArchive()))
        XCTAssertEqual(try Data(contentsOf: outside), bytes)
        XCTAssertTrue(try store.manifest.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink == true)
    }

    func testSymlinkAssetsAndParentDirectoriesCannotReadOrWriteOutsideLibrary() throws {
        let root = try directory(), bytes = try image(), name = SceneAsset.name(for: bytes)
        let outside = root.appendingPathComponent("outside", isDirectory: true)
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        let externalImage = outside.appendingPathComponent(name); try bytes.write(to: externalImage)
        let store = SceneLibraryStore(directory: root.appendingPathComponent("Library"))
        try FileManager.default.createDirectory(at: store.assetsDirectory, withIntermediateDirectories: true)
        let link = try store.assetURL(name)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: externalImage)
        XCTAssertThrowsError(try store.asset(name)); XCTAssertThrowsError(try store.importAsset(bytes))
        XCTAssertEqual(try Data(contentsOf: externalImage), bytes)
        try FileManager.default.removeItem(at: store.assetsDirectory)
        try FileManager.default.createSymbolicLink(at: store.assetsDirectory, withDestinationURL: outside)
        XCTAssertThrowsError(try store.asset(name))
        let different = try image(seed: 100), differentName = SceneAsset.name(for: different)
        XCTAssertThrowsError(try store.importAsset(different))
        XCTAssertFalse(FileManager.default.fileExists(atPath: outside.appendingPathComponent(differentName).path))
        XCTAssertEqual(try Data(contentsOf: externalImage), bytes)
    }

    func testImportRefusesDamagedExistingAssetAndKeepsItForRecovery() throws {
        let root = try directory(), store = SceneLibraryStore(directory: root)
        let good = try image(), name = try store.importAsset(good), url = try store.assetURL(name)
        let damaged = Data("damaged existing source".utf8); try damaged.write(to: url)
        XCTAssertThrowsError(try store.asset(name))
        XCTAssertThrowsError(try store.importAsset(good))
        XCTAssertEqual(try Data(contentsOf: url), damaged)
    }

    func testLibraryDirectoryAndDanglingManifestLinksArePreserved() throws {
        let root = try directory(), outside = root.appendingPathComponent("outside", isDirectory: true)
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        let original = try JSONEncoder().encode(SceneLibraryArchive())
        let externalManifest = outside.appendingPathComponent("scene-library.json")
        try original.write(to: externalManifest)
        let store = SceneLibraryStore(directory: root.appendingPathComponent("Library"))
        try FileManager.default.createSymbolicLink(at: store.directory, withDestinationURL: outside)
        XCTAssertThrowsError(try store.load())
        XCTAssertThrowsError(try store.save(SceneLibraryArchive()))
        XCTAssertEqual(try Data(contentsOf: externalManifest), original)
        XCTAssertTrue(try store.directory.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink == true)

        let dangling = SceneLibraryStore(directory: root.appendingPathComponent("Dangling"))
        try FileManager.default.createDirectory(at: dangling.directory, withIntermediateDirectories: true)
        let missingTarget = root.appendingPathComponent("missing-original.json")
        try FileManager.default.createSymbolicLink(at: dangling.manifest, withDestinationURL: missingTarget)
        XCTAssertThrowsError(try dangling.load())
        XCTAssertThrowsError(try dangling.save(SceneLibraryArchive()))
        XCTAssertEqual(try? FileManager.default.destinationOfSymbolicLink(atPath: dangling.manifest.path), missingTarget.path)
        XCTAssertFalse(FileManager.default.fileExists(atPath: missingTarget.path))
    }

    func testMissingDirectoriesWorkButBrokenAssetLinksAreNotReplaced() throws {
        let root = try directory(), bytes = try image(), name = SceneAsset.name(for: bytes)
        let healthy = SceneLibraryStore(directory: root.appendingPathComponent("Absent"))
        XCTAssertNoThrow(try healthy.load())
        XCTAssertEqual(try healthy.importAsset(bytes), name)
        XCTAssertEqual(try healthy.asset(name), bytes)
        for location in ["root", "Assets", "asset"] {
            let store = SceneLibraryStore(directory: root.appendingPathComponent(location))
            let link: URL
            if location == "root" {
                link = store.directory
            } else if location == "Assets" {
                try FileManager.default.createDirectory(at: store.directory, withIntermediateDirectories: true)
                link = store.assetsDirectory
            } else {
                try FileManager.default.createDirectory(at: store.assetsDirectory, withIntermediateDirectories: true)
                link = try store.assetURL(name)
            }
            let missingTarget = root.appendingPathComponent("missing-" + location)
            try FileManager.default.createSymbolicLink(at: link, withDestinationURL: missingTarget)
            XCTAssertThrowsError(try store.asset(name))
            XCTAssertThrowsError(try store.importAsset(bytes))
            XCTAssertEqual(try? FileManager.default.destinationOfSymbolicLink(atPath: link.path), missingTarget.path)
            XCTAssertFalse(FileManager.default.fileExists(atPath: missingTarget.path))
        }
    }

    func testArchiveRejectsDuplicateIDsAndInvalidSyncStateWithoutChangingManifest() throws {
        let root = try directory(), store = SceneLibraryStore(directory: root)
        var good = try store.load(); good.records = [SavedSceneRecord(scene: try fixture().scene)]
        try store.save(good); let bytes = try Data(contentsOf: store.manifest)
        var duplicate = good; duplicate.records.append(good.records[0])
        var noAccount = good; noAccount.syncEnabled = true
        var orphanBase = good; orphanBase.records[0].baseRevision = UUID()
        var orphanFields = good; orphanFields.records[0].remoteSystemFields = Data([1])
        var badDate = good; badDate.records[0].modified = Date(timeIntervalSince1970: .nan)
        for bad in [duplicate, noAccount, orphanBase, orphanFields, badDate] {
            XCTAssertThrowsError(try store.save(bad))
            XCTAssertEqual(try Data(contentsOf: store.manifest), bytes)
        }
    }

    func testMatchingRevisionAcknowledgementPreservesLocalDisplayMetadataAndProvenance() throws {
        var local = try syncedRecord(); local.baseRevision = nil
        local.modified = Date(timeIntervalSince1970: 900); local.conflictOf = UUID()
        var remote = local; remote.modified = Date(timeIntervalSince1970: 100)
        remote.conflictOf = nil; remote.remoteSystemFields = Data([9])
        var value = archive([local])
        try SceneRevisionMerge.receive(remote, into: &value, account: ownerA)
        let result = try XCTUnwrap(value.records.first)
        XCTAssertEqual(result.scene, local.scene)
        XCTAssertEqual(result.modified, local.modified)
        XCTAssertEqual(result.conflictOf, local.conflictOf)
        XCTAssertEqual(result.remoteSystemFields, remote.remoteSystemFields)
        XCTAssertEqual(result.baseRevision, local.revision); XCTAssertFalse(result.isDirty)
    }

    func testKnownBaseAndStaleAcknowledgementCannotEraseNewerLocalEdit() throws {
        let acknowledged = try syncedRecord()
        var local = acknowledged
        local.scene.name = "Newer local edit"; local.revision = UUID(); local.modified = Date(timeIntervalSince1970: 1)
        var remote = acknowledged
        remote.modified = Date(timeIntervalSince1970: 9_999); remote.remoteSystemFields = Data([8])
        var value = archive([local])
        try SceneRevisionMerge.receive(remote, into: &value, account: ownerA)
        XCTAssertEqual(value.records.count, 1)
        XCTAssertEqual(value.records[0].scene, local.scene)
        XCTAssertEqual(value.records[0].revision, local.revision)
        XCTAssertEqual(value.records[0].baseRevision, acknowledged.revision)
        XCTAssertEqual(value.records[0].modified, local.modified)
        XCTAssertEqual(value.records[0].remoteSystemFields, Data([8]))
        XCTAssertTrue(value.records[0].isDirty)
    }

    func testDivergentRevisionsKeepAnEditableCopyWithoutClockWinner() throws {
        var local = try syncedRecord(), remote = local
        local.revision = UUID(); local.scene.name = "Local office"; local.modified = Date(timeIntervalSince1970: 9_999)
        remote.revision = UUID(); remote.scene.name = "Remote reception"; remote.modified = Date(timeIntervalSince1970: 1)
        let conflictID = UUID(); var value = archive([local])
        try SceneRevisionMerge.receive(remote, into: &value, account: ownerA, conflictID: conflictID)
        XCTAssertEqual(value.records.count, 2)
        let incoming = try XCTUnwrap(value.records.first { $0.id == remote.id })
        let copy = try XCTUnwrap(value.records.first { $0.id == conflictID })
        XCTAssertEqual(incoming.scene, remote.scene); XCTAssertFalse(incoming.isDirty)
        XCTAssertEqual(copy.scene.name, "Local office · kept copy")
        XCTAssertEqual(copy.scene.background, local.scene.background)
        XCTAssertEqual(copy.scene.persona, local.scene.persona)
        XCTAssertEqual(copy.conflictOf, local.id); XCTAssertTrue(copy.isDirty)
        XCTAssertNil(copy.baseRevision); XCTAssertNil(copy.remoteSystemFields)
        XCTAssertEqual(copy.account, ownerA); XCTAssertFalse(copy.isDeleted)
        try SceneRevisionMerge.receive(remote, into: &value, account: ownerA)
        XCTAssertEqual(value.records.count, 2, "Replaying the accepted revision must not make another conflict copy")
    }

    func testUneditedRemoteUpdateAndTombstoneDoNotCreateCopies() throws {
        let local = try syncedRecord(); var remote = local
        remote.revision = UUID(); remote.scene.name = "Remote edit"; remote.isDeleted = true
        var value = archive([local])
        try SceneRevisionMerge.receive(remote, into: &value, account: ownerA)
        XCTAssertEqual(value.records.count, 1)
        XCTAssertTrue(value.records[0].isDeleted); XCTAssertFalse(value.records[0].isDirty)
        XCTAssertEqual(value.records[0].scene, remote.scene)
    }

    func testDirtyDeletionConflictKeepsBothAuthorsWorkAndLocalAssets() throws {
        var local = try syncedRecord(), remote = local
        local.revision = UUID(); local.isDeleted = true
        remote.revision = UUID(); remote.scene.name = "Other device edit"
        let conflictID = UUID(); var value = archive([local])
        try SceneRevisionMerge.receive(remote, into: &value, account: ownerA, conflictID: conflictID)
        let kept = try XCTUnwrap(value.records.first { $0.id == conflictID })
        XCTAssertFalse(kept.isDeleted); XCTAssertTrue(kept.isDirty)
        XCTAssertEqual(kept.scene.assets, local.scene.assets)
        XCTAssertEqual(kept.conflictOf, local.id)
        XCTAssertEqual(value.records.first { $0.id == local.id }?.scene, remote.scene)
    }

    func testAccountAndRevisionReuseRejectionsAreTransactional() throws {
        let local = try syncedRecord()
        for mutate: (inout SavedSceneRecord) -> Void in [
            { $0.account = self.ownerB }, { $0.scene.name = "Same revision, different content" }, { $0.isDeleted = true }
        ] {
            var remote = local; mutate(&remote); var value = archive([local]); let before = value
            XCTAssertThrowsError(try SceneRevisionMerge.receive(remote, into: &value, account: ownerA))
            XCTAssertEqual(value, before)
        }
        var other = local; other.account = ownerB
        var value = archive([other]); let before = value
        XCTAssertThrowsError(try SceneRevisionMerge.receive(local, into: &value, account: ownerA))
        XCTAssertEqual(value, before)
        for identity in ["", "__defaultOwner__", "_defaultOwner", "line\nbreak"] {
            var invalid = ownerA; invalid.userRecordName = identity
            XCTAssertThrowsError(try invalid.validate())
        }
    }

    func testConflictIDCollisionCannotLeaveAnInvalidArchive() throws {
        var local = try syncedRecord(), remote = local
        local.revision = UUID(); local.scene.name = "Local changed"
        remote.revision = UUID(); remote.scene.name = "Remote changed"
        var value = archive([local]); let before = value
        XCTAssertThrowsError(try SceneRevisionMerge.receive(remote, into: &value, account: ownerA, conflictID: local.id))
        XCTAssertEqual(value, before)
        XCTAssertNoThrow(try value.validated())
    }

    func testFullLibraryRejectsIncomingAndConflictWithoutLosingExistingRecords() throws {
        let original = try syncedRecord()
        let records = (0..<1000).map { index in
            var record = original; record.scene.id = UUID(); record.scene.name = "Synthetic scene \(index)"
            return record
        }
        // Being full must not prevent replacing an unchanged, already saved item.
        var full = archive(records), replacement = records[0]
        replacement.revision = UUID(); replacement.scene.name = "Remote update without another slot"
        try SceneRevisionMerge.receive(replacement, into: &full, account: ownerA)
        XCTAssertEqual(full.records.count, 1000)
        XCTAssertEqual(full.records[0].scene, replacement.scene)
        XCTAssertNoThrow(try full.validated())
        for conflict in [false, true] {
            var value = archive(records)
            var remote = original
            if conflict {
                value.records[0].revision = UUID(); value.records[0].scene.name = "Unsaved local edit"
                remote = records[0]; remote.revision = UUID(); remote.scene.name = "Incoming edit"
            }
            let before = value
            XCTAssertNoThrow(try value.validated())
            XCTAssertThrowsError(try SceneRevisionMerge.receive(remote, into: &value, account: ownerA))
            XCTAssertTrue(value == before, "A full library must retain every existing revision when an incoming item needs another slot")
            XCTAssertNoThrow(try value.validated())
        }
    }
}
