import XCTest
import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import CloudKit
@testable import SceneSyncKit

@MainActor final class SceneSyncLifecycleTests: XCTestCase {
    private let ownerA = SceneSyncAccount(container: "iCloud.com.example.scenes", environment: "Production", userRecordName: "_test_owner_a")
    private let ownerB = SceneSyncAccount(container: "iCloud.com.example.scenes", environment: "Production", userRecordName: "_test_owner_b")
    private func directory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("SceneSyncLifecycle-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }; return url
    }
    private func image() throws -> Data {
        let context = try XCTUnwrap(CGContext(data: nil, width: 2, height: 2, bitsPerComponent: 8, bytesPerRow: 8,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(red: 0.2, green: 0.4, blue: 0.6, alpha: 1)); context.fill(CGRect(x: 0, y: 0, width: 2, height: 2))
        let data = NSMutableData(); let writer = try XCTUnwrap(CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(writer, try XCTUnwrap(context.makeImage()), nil); XCTAssertTrue(CGImageDestinationFinalize(writer)); return data as Data
    }
    private func create(_ model: SceneLibraryModel, name: String = "Synthetic scene") throws -> SavedSceneRecord {
        let nameOfAsset = try model.importAsset(image())
        return try model.create(PortableScene(name: name, background: nameOfAsset))
    }
    func testUnsignedLocalLibraryNeverNeedsTransportAndSurvivesRestart() async throws {
        let url = try directory(); let model = SceneLibraryModel(directory: url)
        let record = try create(model); await model.enable()
        XCTAssertFalse(model.isConfigured); XCTAssertFalse(model.isEnabled); XCTAssertNotNil(model.error)
        let reopened = SceneLibraryModel(directory: url)
        XCTAssertEqual(reopened.records, [record]); XCTAssertNil(reopened.error)
        XCTAssertEqual(try reopened.package(for: record.scene).scene, record.scene)
    }
    func testDefaultConfigurationAndMalformedOptInFailClosed() {
        XCTAssertFalse(SceneCloudConfiguration.unavailable.isConfigured)
        for config in [SceneCloudConfiguration(container: "iCloud.example", environment: "Production", isProvisioned: false),
                       .init(container: "iCloud.example/../../x", environment: "Production", isProvisioned: true),
                       .init(container: "iCloud.example", environment: "production", isProvisioned: true)] { XCTAssertFalse(config.isConfigured) }
        XCTAssertTrue(SceneCloudConfiguration(container: "iCloud.example", environment: "Production", isProvisioned: true).isConfigured)
    }
    func testMissingAssetsCannotCommitScene() throws {
        let model = SceneLibraryModel(directory: try directory())
        let name = SceneAsset.name(for: try image())
        XCTAssertThrowsError(try model.create(PortableScene(name: "Missing", background: name)))
        XCTAssertTrue(model.records.isEmpty)
    }
    func testRevisionGuardDeleteDuplicateAndImportPreserveOriginal() throws {
        let url = try directory(); let model = SceneLibraryModel(directory: url); let original = try create(model)
        var edit = original.scene; edit.phoneX = 0.1
        let newer = try model.save(edit, expectedRevision: original.revision)
        XCTAssertThrowsError(try model.save(original.scene, expectedRevision: original.revision))
        XCTAssertThrowsError(try model.delete(id: original.id, expectedRevision: original.revision))
        let copy = try model.duplicate(id: original.id)
        XCTAssertNotEqual(copy.id, original.id); XCTAssertEqual(copy.scene.phoneX, 0.1)
        let imported = try model.importPackage(model.package(for: newer.scene).encoded())
        XCTAssertNotEqual(imported.id, newer.id); XCTAssertEqual(imported.scene.phoneX, 0.1)
        try model.delete(id: newer.id, expectedRevision: newer.revision)
        XCTAssertTrue(try XCTUnwrap(model.records.first(where: { $0.id == newer.id })).isDeleted)
        XCTAssertEqual(try model.package(for: newer.scene).scene, newer.scene)
    }
    func testMigrationMarkerAndCollisionAreAtomicAndIdempotentAfterRestart() throws {
        let url = try directory(); let model = SceneLibraryModel(directory: url); let original = try create(model)
        let imported = try XCTUnwrap(model.migrate(scene: original.scene, sourceID: "legacy-file:one"))
        XCTAssertNotEqual(imported.id, original.id)
        let reopened = SceneLibraryModel(directory: url)
        XCTAssertNil(try reopened.migrate(scene: original.scene, sourceID: "legacy-file:one"))
        XCTAssertEqual(reopened.records.count, 2)
    }
    func testUploadAcknowledgementNeverOverwritesEditMadeDuringUpload() async throws {
        let fake = FakeSceneTransport(account: ownerA); let model = SceneLibraryModel(directory: try directory(), transport: fake)
        let first = try create(model)
        defer { model.cancelRefresh() }
        fake.run = { _, _, uploads, event in
            let snapshot = try XCTUnwrap(uploads.first?.record)
            var edited = snapshot.scene; edited.name = "Edited while uploading"; edited.phoneX = 0.3
            _ = try model.save(edited, expectedRevision: snapshot.revision)
            var receipt = snapshot; receipt.remoteSystemFields = Data([1, 2])
            try event(.acknowledged(receipt)); try event(.checkpoint(Data([7])))
        }
        await model.enable()
        let current = try XCTUnwrap(model.records.first)
        XCTAssertEqual(current.scene.name, "Edited while uploading"); XCTAssertEqual(current.scene.phoneX, 0.3)
        XCTAssertNotEqual(current.revision, first.revision); XCTAssertEqual(current.baseRevision, first.revision); XCTAssertTrue(current.isDirty)
        XCTAssertNil(model.error)
    }
    func testDirtyQueueAndAccountSurviveFailedUploadAndRestart() async throws {
        let url = try directory(); let firstTransport = FakeSceneTransport(account: ownerA)
        firstTransport.run = { _, _, _, _ in throw TestFailure.offline }
        let first = SceneLibraryModel(directory: url, transport: firstTransport); let scene = try create(first)
        await first.enable(); XCTAssertTrue(first.records[0].isDirty); XCTAssertNotNil(first.error)
        let secondTransport = FakeSceneTransport(account: ownerA)
        let reopened = SceneLibraryModel(directory: url, transport: secondTransport)
        await reopened.refresh()
        XCTAssertEqual(secondTransport.uploadedIDs, [scene.id]); XCTAssertFalse(reopened.records[0].isDirty)
        XCTAssertEqual(reopened.records[0].account, ownerA); XCTAssertNil(reopened.error)
    }
    func testAccountReplacementDuringUploadCancelsAndRejectsLateReceipt() async throws {
        let fake = FakeSceneTransport(account: ownerA); let url = try directory()
        let model = SceneLibraryModel(directory: url, transport: fake); _ = try create(model)
        fake.run = { _, _, uploads, event in
            fake.account = self.ownerB; fake.onAccountChange?()
            XCTAssertThrowsError(try event(.acknowledged(try XCTUnwrap(uploads.first?.record))))
            XCTAssertThrowsError(try event(.checkpoint(Data([9]))))
        }
        await model.enable()
        XCTAssertFalse(model.isEnabled); XCTAssertTrue(model.records[0].isDirty); XCTAssertEqual(model.records[0].account, ownerA)
        let count = fake.cycles; await model.enable()
        XCTAssertEqual(fake.cycles, count); XCTAssertFalse(model.isEnabled)
        XCTAssertTrue(model.error?.contains("account changed") == true)
        let archive = try SceneLibraryStore(directory: url).load(); XCTAssertNil(archive.engineState)
    }
    func testDisableRejectsLateCallbacksAndKeepsLocalWork() async throws {
        let fake = FakeSceneTransport(account: ownerA); let model = SceneLibraryModel(directory: try directory(), transport: fake)
        _ = try create(model)
        fake.run = { _, _, uploads, event in
            model.disable()
            XCTAssertThrowsError(try event(.acknowledged(try XCTUnwrap(uploads.first?.record))))
        }
        await model.enable(); XCTAssertFalse(model.isEnabled); XCTAssertFalse(model.isBusy); XCTAssertTrue(model.records[0].isDirty)
    }
    func testRemoteConflictPreservesBothAndOldAcknowledgementCannotEraseRemote() async throws {
        let fake = FakeSceneTransport(account: ownerA); let model = SceneLibraryModel(directory: try directory(), transport: fake)
        let original = try create(model)
        fake.run = { account, _, uploads, event in
            let outgoing = try XCTUnwrap(uploads.first)
            var remoteScene = outgoing.record.scene; remoteScene.name = "Other device edit"
            var remote = SavedSceneRecord(scene: remoteScene); remote.account = account
            let remotePackage = ScenePackage(scene: remoteScene, assets: outgoing.package.assets)
            try event(.received(remote, remotePackage)); try event(.acknowledged(outgoing.record))
        }
        await model.enable()
        XCTAssertEqual(model.records.count, 2)
        let server = try XCTUnwrap(model.records.first(where: { $0.id == original.id }))
        XCTAssertEqual(server.scene.name, "Other device edit"); XCTAssertFalse(server.isDirty)
        let kept = try XCTUnwrap(model.records.first(where: { $0.conflictOf == original.id }))
        XCTAssertTrue(kept.isDirty); XCTAssertFalse(kept.isDeleted)
    }
    func testRemotePackageMismatchCannotInstallOrAdvanceCheckpoint() async throws {
        let fake = FakeSceneTransport(account: ownerA); let url = try directory(); let model = SceneLibraryModel(directory: url, transport: fake)
        _ = try create(model)
        fake.run = { account, _, uploads, event in
            let upload = try XCTUnwrap(uploads.first); var record = upload.record; record.account = account; record.scene.name = "Forged mismatch"
            try event(.received(record, upload.package)); try event(.checkpoint(Data([8])))
        }
        await model.enable(); XCTAssertNotNil(model.error); XCTAssertEqual(model.records[0].scene.name, "Synthetic scene")
        XCTAssertNil(try SceneLibraryStore(directory: url).load().engineState)
    }
    func testCheckpointWriteFailureHaltsRatherThanOverwritingExternalManifest() async throws {
        let fake = FakeSceneTransport(account: ownerA); let url = try directory(); let model = SceneLibraryModel(directory: url, transport: fake)
        _ = try create(model); let sentinel = Data("external edit must survive".utf8)
        fake.run = { _, _, _, event in
            try sentinel.write(to: url.appendingPathComponent("scene-library.json"), options: .atomic)
            try event(.checkpoint(Data([7])))
            XCTFail("A failed checkpoint must throw and stop the transport")
        }
        await model.enable(); XCTAssertNotNil(model.error); XCTAssertFalse(model.isEnabled); XCTAssertFalse(model.isBusy)
        XCTAssertEqual(try Data(contentsOf: url.appendingPathComponent("scene-library.json")), sentinel)
        XCTAssertThrowsError(try model.duplicate(id: model.records[0].id))
    }
    func testLocalReorderRequiresExactLiveIDsAndKeepsTombstonesAndRevisions() throws {
        let model = SceneLibraryModel(directory: try directory())
        let one = try create(model, name: "One"), two = try create(model, name: "Two"), three = try create(model, name: "Three")
        try model.delete(id: three.id, expectedRevision: three.revision)
        XCTAssertThrowsError(try model.reorder(ids: [one.id, one.id]))
        XCTAssertThrowsError(try model.reorder(ids: [one.id]))
        try model.reorder(ids: [two.id, one.id])
        XCTAssertEqual(model.records.filter { !$0.isDeleted }.map(\.id), [two.id, one.id])
        XCTAssertEqual(model.records.first?.revision, two.revision); XCTAssertTrue(model.records.last?.isDeleted == true)
    }
    func testCancelRefreshKeepsOptInButDropsLateReceipt() async throws {
        let fake = FakeSceneTransport(account: ownerA); let model = SceneLibraryModel(directory: try directory(), transport: fake)
        _ = try create(model)
        fake.run = { _, _, uploads, event in
            model.cancelRefresh()
            XCTAssertThrowsError(try event(.acknowledged(try XCTUnwrap(uploads.first?.record))))
        }
        await model.enable(); XCTAssertTrue(model.isEnabled); XCTAssertFalse(model.isBusy); XCTAssertTrue(model.records[0].isDirty)
    }
    func testReceivedPackageIsDurableBeforeCheckpointAndReopensOffline() async throws {
        let fake = FakeSceneTransport(account: ownerA); let url = try directory(); let model = SceneLibraryModel(directory: url, transport: fake)
        let bytes = try image(); let name = SceneAsset.name(for: bytes)
        let scene = PortableScene(name: "Other device", background: name)
        fake.run = { account, _, _, event in
            var record = SavedSceneRecord(scene: scene); record.account = account
            try event(.received(record, ScenePackage(scene: scene, assets: [name: bytes])))
            try event(.checkpoint(Data([3])))
        }
        await model.enable(); XCTAssertNil(model.error)
        let reopened = SceneLibraryModel(directory: url)
        XCTAssertEqual(reopened.records.first?.scene, scene)
        XCTAssertEqual(try reopened.package(for: scene).assets[name], bytes)
        XCTAssertEqual(try SceneLibraryStore(directory: url).load().engineState, Data([3]))
    }
    func testFullLibraryRejectsNewSceneWithoutBlockingExistingEdits() throws {
        let url = try directory(); let store = SceneLibraryStore(directory: url); var archive = try store.load()
        let asset = try store.importAsset(image())
        archive.records = (0..<1000).map { SavedSceneRecord(scene: PortableScene(name: "Scene \($0)", background: asset)) }
        try store.save(archive)
        let model = SceneLibraryModel(directory: url)
        XCTAssertThrowsError(try model.create(PortableScene(name: "Over limit", background: asset)))
        XCTAssertFalse(model.isStorageBlocked)
        var edited = try XCTUnwrap(model.records.first).scene; edited.name = "Still editable"
        _ = try model.save(edited, expectedRevision: model.records[0].revision)
        XCTAssertEqual(model.records[0].scene.name, "Still editable")
    }
    func testCloudEnvelopeAcceptsOnlyExactCurrentPrivateOwnerOrDocumentedAlias() throws {
        let model = SceneLibraryModel(directory: try directory()); let saved = try create(model)
        let metadata = SceneCloudMetadata(saved, account: ownerA)
        func cloudRecord(owner: String, zone: String = "WorkbenchScenesV1", type: String = "SceneV1") throws -> CKRecord {
            let id = CKRecord.ID(recordName: saved.id.uuidString, zoneID: CKRecordZone.ID(zoneName: zone, ownerName: owner))
            let record = CKRecord(recordType: type, recordID: id)
            record["metadata"] = try JSONEncoder().encode(metadata) as CKRecordValue; return record
        }
        for owner in [ownerA.userRecordName, CKCurrentUserDefaultName] {
            XCTAssertEqual(try SceneCloudMetadata.decode(cloudRecord(owner: owner), account: ownerA), metadata)
        }
        for owner in [ownerB.userRecordName, "__defaultOwner__", "_test_owner_a-extra"] where owner != CKCurrentUserDefaultName {
            XCTAssertThrowsError(try SceneCloudMetadata.decode(cloudRecord(owner: owner), account: ownerA))
        }
        XCTAssertThrowsError(try SceneCloudMetadata.decode(cloudRecord(owner: ownerA.userRecordName, zone: "WorkbenchPhotosV1"), account: ownerA))
        XCTAssertThrowsError(try SceneCloudMetadata.decode(cloudRecord(owner: ownerA.userRecordName, type: "PhotoV1"), account: ownerA))
        XCTAssertThrowsError(try SceneSyncAccount(container: ownerA.container, environment: ownerA.environment, userRecordName: "").validate())
        let alias = try cloudRecord(owner: CKCurrentUserDefaultName)
        XCTAssertThrowsError(try SceneCloudMetadata.decode(alias, account: ownerB)) // Alias never bypasses the envelope's captured identity.
        var malformed = metadata; malformed.version = 2
        alias["metadata"] = try JSONEncoder().encode(malformed) as CKRecordValue
        XCTAssertThrowsError(try SceneCloudMetadata.decode(alias, account: ownerA))
        alias["metadata"] = Data(repeating: 0, count: 4097) as CKRecordValue
        XCTAssertThrowsError(try SceneCloudMetadata.decode(alias, account: ownerA))
    }
    func testAutomaticSyncCoalescesLocalEditsWithoutAcknowledgementLoop() async throws {
        let fake = FakeSceneTransport(account: ownerA), clock = SceneAutomaticSyncClock()
        let model = SceneLibraryModel(directory: try directory(), transport: fake, automaticSyncDelay: { await clock.wait() })
        defer { model.cancelRefresh(); clock.releaseAll() }
        _ = try create(model); await model.enable(); XCTAssertEqual(fake.cycles, 1)
        for name in ["First", "Second", "Final"] {
            let current = model.records[0]; var scene = current.scene; scene.name = name
            _ = try model.save(scene, expectedRevision: current.revision)
        }
        await clock.started(3)
        XCTAssertEqual(fake.cycles, 1)
        let pending = try XCTUnwrap(model.scheduledSync); clock.releaseAll(); await pending.value
        XCTAssertEqual(fake.cycles, 2); XCTAssertEqual(model.records[0].scene.name, "Final")
        XCTAssertFalse(model.records[0].isDirty); XCTAssertNil(model.scheduledSync)
    }
    func testDisableAndBackgroundCancelScheduledWorkEvenWhenDelayIgnoresCancellation() async throws {
        for turnOff in [false, true] {
            let fake = FakeSceneTransport(account: ownerA), clock = SceneAutomaticSyncClock()
            let model = SceneLibraryModel(directory: try directory(), transport: fake, automaticSyncDelay: { await clock.wait() })
            _ = try create(model); await model.enable()
            let current = model.records[0]; var scene = current.scene; scene.name = "Queued"
            _ = try model.save(scene, expectedRevision: current.revision); await clock.started(1)
            let pending = try XCTUnwrap(model.scheduledSync)
            if turnOff { model.disable() } else { model.cancelRefresh() }
            clock.releaseAll(); await pending.value
            XCTAssertEqual(fake.cycles, 1); XCTAssertNil(model.scheduledSync); XCTAssertTrue(model.records[0].isDirty)
            var later = model.records[0].scene; later.name = "Saved after background callback"
            _ = try model.save(later, expectedRevision: model.records[0].revision)
            XCTAssertNil(model.scheduledSync)
            if !turnOff { await model.refresh(); XCTAssertEqual(fake.cycles, 2); XCTAssertFalse(model.records[0].isDirty) }
        }
    }
    func testLocalEditDuringUploadSchedulesExactlyOneFollowOnAfterSuccess() async throws {
        let fake = FakeSceneTransport(account: ownerA), clock = SceneAutomaticSyncClock()
        let model = SceneLibraryModel(directory: try directory(), transport: fake, automaticSyncDelay: { await clock.wait() })
        defer { model.cancelRefresh(); clock.releaseAll() }
        _ = try create(model)
        fake.run = { _, _, uploads, event in
            let snapshot = try XCTUnwrap(uploads.first?.record)
            if fake.cycles == 1 {
                var changed = snapshot.scene; changed.name = "Written during upload"
                _ = try model.save(changed, expectedRevision: snapshot.revision)
                XCTAssertNil(model.scheduledSync)
            }
            try event(.acknowledged(snapshot)); try event(.checkpoint(Data([1])))
        }
        await model.enable(); XCTAssertTrue(model.records[0].isDirty)
        await clock.started(1); let followOn = try XCTUnwrap(model.scheduledSync)
        clock.releaseAll(); await followOn.value
        XCTAssertEqual(fake.cycles, 2); XCTAssertFalse(model.records[0].isDirty)
        XCTAssertEqual(model.records[0].scene.name, "Written during upload"); XCTAssertNil(model.scheduledSync)
    }
    func testFailedAutomaticUploadWaitsForExplicitRetryEvenAfterMoreEdits() async throws {
        let fake = FakeSceneTransport(account: ownerA), clock = SceneAutomaticSyncClock()
        let model = SceneLibraryModel(directory: try directory(), transport: fake, automaticSyncDelay: { await clock.wait() })
        defer { model.cancelRefresh(); clock.releaseAll() }
        _ = try create(model); await model.enable()
        fake.run = { _, _, _, _ in
            var duringFailure = model.records[0].scene; duringFailure.name = "Edit during failed upload"
            _ = try model.save(duringFailure, expectedRevision: model.records[0].revision)
            throw TestFailure.offline
        }
        var edited = model.records[0].scene; edited.name = "Offline edit"
        _ = try model.save(edited, expectedRevision: model.records[0].revision); await clock.started(1)
        let pending = try XCTUnwrap(model.scheduledSync); clock.releaseAll(); await pending.value
        XCTAssertEqual(fake.cycles, 2); XCTAssertNotNil(model.error); XCTAssertNil(model.scheduledSync)
        XCTAssertEqual(model.records[0].scene.name, "Edit during failed upload")
        edited.name = "Another offline edit"; _ = try model.save(edited, expectedRevision: model.records[0].revision)
        XCTAssertNil(model.scheduledSync); XCTAssertEqual(fake.cycles, 2)
        fake.run = nil; await model.refresh()
        XCTAssertEqual(fake.cycles, 3); XCTAssertFalse(model.records[0].isDirty); XCTAssertNil(model.error)
    }
    func testNoOpSaveAndRepeatedTombstoneDoNotCreateUploadWork() async throws {
        let fake = FakeSceneTransport(account: ownerA), clock = SceneAutomaticSyncClock()
        let model = SceneLibraryModel(directory: try directory(), transport: fake, automaticSyncDelay: { await clock.wait() })
        defer { model.cancelRefresh(); clock.releaseAll() }
        _ = try create(model); await model.enable()
        let current = model.records[0]
        let unchanged = try model.save(current.scene, expectedRevision: current.revision)
        XCTAssertEqual(unchanged.revision, current.revision); XCTAssertNil(model.scheduledSync)
        try model.delete(id: current.id, expectedRevision: current.revision); await clock.started(1)
        let pending = try XCTUnwrap(model.scheduledSync); clock.releaseAll(); await pending.value
        let deleted = model.records[0]
        try model.delete(id: deleted.id, expectedRevision: deleted.revision)
        XCTAssertEqual(model.records[0].revision, deleted.revision); XCTAssertNil(model.scheduledSync); XCTAssertEqual(fake.cycles, 2)
    }
    func testRemoteReceiptsAndReorderingNeverScheduleAnUpload() async throws {
        let fake = FakeSceneTransport(account: ownerA), clock = SceneAutomaticSyncClock()
        let model = SceneLibraryModel(directory: try directory(), transport: fake, automaticSyncDelay: { await clock.wait() })
        defer { model.cancelRefresh(); clock.releaseAll() }
        let data = try image(), name = SceneAsset.name(for: data)
        let scene = PortableScene(name: "Remote", background: name)
        fake.run = { account, _, _, event in
            var remote = SavedSceneRecord(scene: scene); remote.account = account
            try event(.received(remote, ScenePackage(scene: scene, assets: [name: data])))
            try event(.checkpoint(Data([2])))
        }
        await model.enable(); XCTAssertNil(model.scheduledSync)
        try model.reorder(ids: [scene.id]); XCTAssertNil(model.scheduledSync); XCTAssertEqual(clock.count, 0)
    }
    func testNewScenesAndTombstonesAutoSendOnlyWhenAlreadyOptedIn() async throws {
        let fake = FakeSceneTransport(account: ownerA), clock = SceneAutomaticSyncClock()
        let model = SceneLibraryModel(directory: try directory(), transport: fake, automaticSyncDelay: { await clock.wait() })
        defer { model.cancelRefresh(); clock.releaseAll() }
        let before = try create(model); XCTAssertNil(model.scheduledSync); XCTAssertEqual(fake.cycles, 0)
        await model.enable(); XCTAssertEqual(fake.cycles, 1)
        let after = try create(model, name: "Created after opt-in"); await clock.started(1)
        let created = try XCTUnwrap(model.scheduledSync); clock.releaseAll(); await created.value
        XCTAssertEqual(fake.cycles, 2); XCTAssertFalse(try XCTUnwrap(model.records.first(where: { $0.id == after.id })).isDirty)
        let current = try XCTUnwrap(model.records.first(where: { $0.id == before.id }))
        try model.delete(id: current.id, expectedRevision: current.revision); await clock.started(2)
        let deletion = try XCTUnwrap(model.scheduledSync); clock.releaseAll(); await deletion.value
        let deleted = try XCTUnwrap(model.records.first(where: { $0.id == before.id }))
        XCTAssertTrue(deleted.isDeleted); XCTAssertFalse(deleted.isDirty); XCTAssertEqual(fake.cycles, 3); XCTAssertNil(model.scheduledSync)
    }
    func testAccountChangeCancelsPendingTimerAndNeverSendsToReplacement() async throws {
        let fake = FakeSceneTransport(account: ownerA), clock = SceneAutomaticSyncClock()
        let model = SceneLibraryModel(directory: try directory(), transport: fake, automaticSyncDelay: { await clock.wait() })
        defer { model.cancelRefresh(); clock.releaseAll() }
        _ = try create(model); await model.enable()
        var scene = model.records[0].scene; scene.name = "Waiting for old account"
        _ = try model.save(scene, expectedRevision: model.records[0].revision); await clock.started(1)
        let pending = try XCTUnwrap(model.scheduledSync)
        fake.account = ownerB; fake.onAccountChange?(); clock.releaseAll(); await pending.value
        XCTAssertEqual(fake.cycles, 1); XCTAssertFalse(model.isEnabled); XCTAssertNil(model.scheduledSync)
        XCTAssertEqual(model.records[0].account, ownerA); XCTAssertTrue(model.records[0].isDirty)
    }
    func testCorruptLibraryIsKeptAndNotReplacedWithEmptyArchive() throws {
        let url = try directory(); let bytes = Data("corrupt but recoverable original".utf8)
        try bytes.write(to: url.appendingPathComponent("scene-library.json"))
        let model = SceneLibraryModel(directory: url); XCTAssertNotNil(model.error)
        XCTAssertThrowsError(try create(model)); model.disable()
        XCTAssertEqual(try Data(contentsOf: url.appendingPathComponent("scene-library.json")), bytes)
    }
}

private enum TestFailure: Error { case offline }
@MainActor private final class FakeSceneTransport: SceneSyncTransport {
    var onAccountChange: (@MainActor @Sendable () -> Void)?
    var account: SceneSyncAccount
    var cycles = 0
    var uploadedIDs: [UUID] = []
    var run: (@MainActor (SceneSyncAccount, Data?, [SceneSyncUpload], @MainActor @Sendable (SceneSyncEvent) throws -> Void) async throws -> Void)?
    init(account: SceneSyncAccount) { self.account = account }
    func currentAccount() async throws -> SceneSyncAccount { account }
    func cancel() {}
    func synchronize(account: SceneSyncAccount, state: Data?, uploads: [SceneSyncUpload],
                     onEvent: @escaping @MainActor @Sendable (SceneSyncEvent) throws -> Void) async throws {
        cycles += 1; uploadedIDs += uploads.map(\.record.id)
        if let run { try await run(account, state, uploads, onEvent) }
        else { for upload in uploads { try onEvent(.acknowledged(upload.record)) } }
    }
}

/// Deliberately noncooperative: releasing a cancelled wait must still be safe.
@MainActor private final class SceneAutomaticSyncClock {
    private(set) var count = 0
    private var waits: [CheckedContinuation<Void, Never>] = []
    private var startedWaits: [(Int, CheckedContinuation<Void, Never>)] = []
    func wait() async {
        await withCheckedContinuation { continuation in
            count += 1; waits.append(continuation)
            let ready = startedWaits.filter { $0.0 <= count }; startedWaits.removeAll { $0.0 <= count }
            ready.forEach { $0.1.resume() }
        }
    }
    func started(_ number: Int) async {
        if count >= number { return }
        await withCheckedContinuation { startedWaits.append((number, $0)) }
    }
    func releaseAll() { let old = waits; waits.removeAll(); old.forEach { $0.resume() } }
}
