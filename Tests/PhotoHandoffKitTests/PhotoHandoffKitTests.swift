import XCTest
import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import CloudKit
@testable import PhotoHandoffKit

@MainActor final class PhotoHandoffKitTests: XCTestCase {
    private func directory() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("PhotoHandoffTests-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        return root
    }
    private func image(gray: CGFloat = 0.4, orientation: Int = 1) throws -> Data {
        let context = try XCTUnwrap(CGContext(data: nil, width: 80, height: 40, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue))
        context.setFillColor(CGColor(gray: gray, alpha: 1)); context.fill(CGRect(x: 0, y: 0, width: 80, height: 40))
        let data = NSMutableData()
        let destination = try XCTUnwrap(CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, try XCTUnwrap(context.makeImage()), [
            kCGImagePropertyOrientation: orientation,
            kCGImagePropertyGPSDictionary: [kCGImagePropertyGPSLatitude: 37.5, kCGImagePropertyGPSLatitudeRef: "N"],
            kCGImagePropertyExifDictionary: [kCGImagePropertyExifUserComment: "Private fixture comment"]
        ] as CFDictionary)
        XCTAssertTrue(CGImageDestinationFinalize(destination)); return data as Data
    }
    private func add(_ model: PhotoHandoffModel, gray: CGFloat = 0.4) async throws -> UUID {
        let result = await model.addPhoto(data: try image(gray: gray), title: "Synthetic photo")
        return try XCTUnwrap(result)
    }
    private func remote(_ data: Data, id: UUID = UUID()) throws -> (RemoteHandoffPhoto, Data) {
        let prepared = try PhotoMedia.prepare(data)
        return (RemoteHandoffPhoto(id: id, title: "From synthetic phone", created: Date(timeIntervalSince1970: 100),
            sourceDevice: "iPhone fixture", digest: prepared.digest, byteCount: prepared.jpeg.count,
            width: prepared.width, height: prepared.height), prepared.jpeg)
    }

    func testNormalizationTransformsOrientationAndDropsSourceLocationAndComment() throws {
        let original = try image(orientation: 6)
        let prepared = try PhotoMedia.prepare(original)
        XCTAssertEqual(prepared.width, 40); XCTAssertEqual(prepared.height, 80)
        let source = try XCTUnwrap(CGImageSourceCreateWithData(prepared.jpeg as CFData, nil))
        let properties = try XCTUnwrap(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any])
        XCTAssertNil(properties[kCGImagePropertyGPSDictionary])
        XCTAssertNil((properties[kCGImagePropertyExifDictionary] as? [CFString: Any])?[kCGImagePropertyExifUserComment])
        XCTAssertNotEqual(original, prepared.jpeg)
    }

    func testProvisioningMarkerAcceptsOnlyExplicitBooleanAndBuildValues() {
        for value: Any in [true, "YES", "true", "1"] {
            XCTAssertTrue(PhotoCloudConfiguration.acceptsProvisionedMarker(value))
        }
        for value: Any in [false, "NO", "false", "0", "yes", " YES ", "$(WORKBENCH_PHOTO_CLOUD_PROVISIONED)", 1, 2] {
            XCTAssertFalse(PhotoCloudConfiguration.acceptsProvisionedMarker(value))
        }
        XCTAssertFalse(PhotoCloudConfiguration.acceptsProvisionedMarker(nil))
    }

    func testCloudDeletionReplayAcceptsOnlyMissingRequestedRecord() {
        let zone = CKRecordZone.ID(zoneName: "WorkbenchPhotosV1", ownerName: "owner-a")
        let requested = CKRecord.ID(recordName: UUID().uuidString, zoneID: zone)
        let other = CKRecord.ID(recordName: UUID().uuidString, zoneID: zone)
        let missing = CKError(.unknownItem)
        let wrapped = CKError(.partialFailure, userInfo: [CKPartialErrorsByItemIDKey: [requested: missing]])
        XCTAssertTrue(CloudPhotoTransport.isAlreadyRemoved(wrapped, recordID: requested))
        XCTAssertFalse(CloudPhotoTransport.isAlreadyRemoved(wrapped, recordID: other))
        let denied = CKError(.partialFailure, userInfo: [CKPartialErrorsByItemIDKey: [requested: CKError(.permissionFailure)]])
        XCTAssertFalse(CloudPhotoTransport.isAlreadyRemoved(denied, recordID: requested))
    }

    func testMissingAndCorruptDerivedJPEGRepairWithoutChangeReplayOrOriginalLoss() async throws {
        let root = try directory(), fake = FakePhotoTransport()
        let model = PhotoHandoffModel(directory: root, platform: "iPhone", transport: fake)
        await model.enable(); let id = try await add(model); await model.sendPhoto(id)
        let photo = model.photos[0], url = try XCTUnwrap(model.fileURL(for: model.photos[0]))
        let originalURL = url.deletingLastPathComponent().appendingPathComponent("original.bin")
        let original = try Data(contentsOf: originalURL), jpeg = try Data(contentsOf: url)
        fake.hideChangeRecords = true
        try FileManager.default.removeItem(at: url)
        await model.refresh()
        XCTAssertNil(model.error); XCTAssertEqual(try Data(contentsOf: url), jpeg)
        XCTAssertEqual(try Data(contentsOf: originalURL), original)
        XCTAssertEqual(model.photos[0], photo)
        try Data([1, 2, 3]).write(to: url)
        await model.refresh()
        XCTAssertNil(model.error); XCTAssertEqual(try Data(contentsOf: url), jpeg)
        XCTAssertEqual(try Data(contentsOf: originalURL), original)
        XCTAssertEqual(model.photos[0], photo); XCTAssertEqual(fake.downloads, 2)
    }

    func testForegroundPaginationIsBoundedAndCommitsEachPage() async throws {
        let root = try directory(), fake = FakePhotoTransport()
        fake.pages = (1...4).map { PhotoChangePage(photos: [], checkpoint: Data([UInt8($0)]), hasMore: $0 < 4) }
        let model = PhotoHandoffModel(directory: root, platform: "Mac", transport: fake)
        await model.enable()
        XCTAssertEqual(fake.changeCalls, 3)
        XCTAssertEqual(try PhotoHandoffStore(directory: root).load().accounts[0].checkpoint, Data([3]))
        await model.refresh()
        XCTAssertEqual(fake.changeCalls, 4)
        XCTAssertEqual(try PhotoHandoffStore(directory: root).load().accounts[0].checkpoint, Data([4]))
    }

    func testRetryAfterIsDurableAndPreventsEarlyNetworkRetry() async throws {
        let root = try directory(), fake = FakePhotoTransport()
        let model = PhotoHandoffModel(directory: root, platform: "iPhone", transport: fake)
        await model.enable(); let id = try await add(model)
        let retry = Date().addingTimeInterval(3600)
        fake.uploadFailure = .retryAfter(retry, "Synthetic rate limit")
        await model.sendPhoto(id)
        XCTAssertEqual(model.photos[0].statusLabel, "Queued for iCloud")
        let calls = fake.identityCalls
        let reopened = PhotoHandoffModel(directory: root, platform: "iPhone", transport: fake)
        await reopened.refresh()
        XCTAssertEqual(fake.identityCalls, calls); XCTAssertTrue(fake.uploads.isEmpty)
        XCTAssertEqual(try PhotoHandoffStore(directory: root).load().accounts[0].retryNotBefore, retry)
    }

    func testCaptureIsLocalOriginalSurvivesRestartAndUnsignedModeCannotCallCloud() async throws {
        let root = try directory(), fake = FakePhotoTransport()
        let model = PhotoHandoffModel(directory: root, platform: "iPhone", allowsCloudAccess: false, transport: fake)
        let original = try image()
        let result = await model.addPhoto(data: original, title: "../../A name is not a path")
        let id = try XCTUnwrap(result)
        XCTAssertFalse(model.isConfigured)
        await model.enable(); await model.sendPhoto(id); await model.refresh()
        XCTAssertEqual(fake.identityCalls, 0); XCTAssertEqual(fake.uploads.count, 0)
        let originalURL = root.appendingPathComponent("Photos/\(id.uuidString)/original.bin")
        XCTAssertEqual(try Data(contentsOf: originalURL), original)
        let reopened = PhotoHandoffModel(directory: root, platform: "iPhone", allowsCloudAccess: false)
        XCTAssertEqual(reopened.photos.count, 1)
        XCTAssertEqual(reopened.photos[0].statusLabel, "Only on this device")
        XCTAssertNotNil(reopened.fileURL(for: reopened.photos[0]))
    }

    func testOfflineExplicitSendRetainsOwnerAndRetriesAfterRestartWithoutDuplicating() async throws {
        let root = try directory(), fake = FakePhotoTransport()
        let model = PhotoHandoffModel(directory: root, platform: "iPhone", transport: fake)
        await model.enable()
        let id = try await add(model)
        XCTAssertEqual(fake.uploads.count, 0)
        fake.offline = true
        await model.sendPhoto(id)
        XCTAssertEqual(model.photos[0].statusLabel, "Queued for iCloud")
        XCTAssertEqual(try PhotoHandoffStore(directory: root).load().photos[0].account, fake.account)
        fake.offline = false
        let reopened = PhotoHandoffModel(directory: root, platform: "iPhone", transport: fake)
        await reopened.refresh(); await reopened.refresh()
        XCTAssertEqual(fake.uploads.count, 1)
        XCTAssertEqual(reopened.photos.count, 1)
        XCTAssertTrue(reopened.photos[0].isUploaded)
        XCTAssertEqual(reopened.photos[0].statusLabel, "In iCloud")
    }

    func testAccountChangeDuringNoncooperativeUploadCannotCommitOrRetargetOldQueue() async throws {
        let root = try directory(), fake = FakePhotoTransport()
        let model = PhotoHandoffModel(directory: root, platform: "iPhone", transport: fake)
        await model.enable(); let id = try await add(model)
        fake.holdUpload = true
        let sending = Task { await model.sendPhoto(id) }
        await fake.waitForUpload()
        let ownerA = fake.account
        fake.switchAccount(to: FakePhotoTransport.ownerB)
        XCTAssertFalse(model.isEnabled)
        fake.finishUpload(); await sending.value
        XCTAssertFalse(model.photos[0].isUploaded)
        XCTAssertEqual(try PhotoHandoffStore(directory: root).load().photos[0].account, ownerA)
        await model.enable(); await model.refresh()
        XCTAssertTrue(model.photos.isEmpty)
        XCTAssertEqual(fake.uploads.map(\.1), [ownerA])
        XCTAssertNil(fake.records[FakePhotoTransport.ownerB]?[id])
        XCTAssertNotNil(fake.records[ownerA]?[id])
    }

    func testDisableDuringUploadKeepsQueueAndRejectsLateAcknowledgement() async throws {
        let root = try directory(), fake = FakePhotoTransport()
        let model = PhotoHandoffModel(directory: root, platform: "iPhone", transport: fake)
        await model.enable(); let id = try await add(model)
        fake.holdUpload = true
        let sending = Task { await model.sendPhoto(id) }
        await fake.waitForUpload(); model.disable()
        fake.finishUpload(); await sending.value
        XCTAssertFalse(model.isEnabled); XCTAssertFalse(model.isBusy)
        XCTAssertEqual(model.photos[0].statusLabel, "Queued for iCloud")
        let reopened = PhotoHandoffModel(directory: root, platform: "iPhone", transport: fake)
        await reopened.refresh()
        XCTAssertFalse(reopened.isEnabled); XCTAssertEqual(fake.uploads.count, 1)
    }

    func testDifferentAccountAtRelaunchPausesBeforeSending() async throws {
        let root = try directory(), fake = FakePhotoTransport()
        let model = PhotoHandoffModel(directory: root, platform: "iPhone", transport: fake)
        await model.enable(); let id = try await add(model)
        fake.offline = true; await model.sendPhoto(id)
        fake.offline = false; fake.account = FakePhotoTransport.ownerB
        let reopened = PhotoHandoffModel(directory: root, platform: "iPhone", transport: fake)
        await reopened.refresh()
        XCTAssertFalse(reopened.isEnabled); XCTAssertTrue(fake.uploads.isEmpty)
        XCTAssertEqual(try PhotoHandoffStore(directory: root).load().photos[0].account, FakePhotoTransport.ownerA)
    }

    func testDamagedDownloadKeepsCheckpointAndGoodReplayIsIdempotent() async throws {
        let root = try directory(), fake = FakePhotoTransport()
        let entry = try remote(image())
        fake.records[fake.account] = [entry.0.id: entry]
        fake.corruptDownloads = true
        let model = PhotoHandoffModel(directory: root, platform: "Mac", transport: fake)
        await model.enable()
        XCTAssertTrue(model.photos.isEmpty); XCTAssertNotNil(model.error)
        XCTAssertNil(try PhotoHandoffStore(directory: root).load().accounts[0].checkpoint)
        fake.corruptDownloads = false
        await model.refresh(); await model.refresh()
        XCTAssertEqual(model.photos.count, 1)
        XCTAssertEqual(model.photos[0].id, entry.0.id)
        XCTAssertEqual(try PhotoHandoffStore(directory: root).load().accounts[0].checkpoint, Data([1]))
        XCTAssertNotNil(model.fileURL(for: model.photos[0]))
    }

    func testConflictingUUIDDoesNotOverwritePreviouslyDownloadedBytesOrAdvanceCheckpoint() async throws {
        let root = try directory(), fake = FakePhotoTransport()
        let first = try remote(image())
        fake.records[fake.account] = [first.0.id: first]
        let model = PhotoHandoffModel(directory: root, platform: "Mac", transport: fake)
        await model.enable()
        let url = try XCTUnwrap(model.fileURL(for: model.photos[0]))
        fake.records[fake.account] = [first.0.id: try remote(image(gray: 0.9), id: first.0.id)]
        fake.checkpoint = Data([2]); await model.refresh()
        XCTAssertNotNil(model.error)
        XCTAssertEqual(try Data(contentsOf: url), first.1)
        XCTAssertEqual(try PhotoHandoffStore(directory: root).load().accounts[0].checkpoint, Data([1]))
    }

    func testLocalRemovalReceiptPreventsRedownloadAfterRestart() async throws {
        let root = try directory(), fake = FakePhotoTransport()
        let entry = try remote(image())
        fake.records[fake.account] = [entry.0.id: entry]
        let model = PhotoHandoffModel(directory: root, platform: "Mac", transport: fake)
        await model.enable(); try model.removeLocalPhoto(entry.0.id)
        let reopened = PhotoHandoffModel(directory: root, platform: "Mac", transport: fake)
        await reopened.refresh()
        XCTAssertTrue(reopened.photos.isEmpty)
        XCTAssertNotNil(fake.records[fake.account]?[entry.0.id])
        XCTAssertEqual(fake.downloads, 1)
    }

    func testCloudRemovalIntentSurvivesFailureAndNeverResendsDeletedPhoto() async throws {
        let root = try directory(), fake = FakePhotoTransport()
        let model = PhotoHandoffModel(directory: root, platform: "iPhone", transport: fake)
        await model.enable(); let id = try await add(model); await model.sendPhoto(id)
        fake.failRemoval = true; await model.removeFromCloud(id)
        XCTAssertEqual(model.photos[0].statusLabel, "Removal queued")
        fake.failRemoval = false
        let reopened = PhotoHandoffModel(directory: root, platform: "iPhone", transport: fake)
        await reopened.refresh(); await reopened.sendPhoto(id)
        XCTAssertFalse(reopened.photos[0].isUploaded)
        XCTAssertEqual(fake.uploads.count, 1); XCTAssertNil(fake.records[fake.account]?[id])
        XCTAssertNotNil(reopened.fileURL(for: reopened.photos[0]))
    }

    func testCorruptFutureLibraryStaysUntouchedAndInvalidMediaNeverPublishes() async throws {
        let root = try directory()
        let manifest = root.appendingPathComponent("photos.json")
        let bytes = Data("{\"version\":999,\"photos\":[],\"enabled\":false,\"accounts\":[],\"suppressed\":[]}".utf8)
        try bytes.write(to: manifest)
        let model = PhotoHandoffModel(directory: root, platform: "Mac", allowsCloudAccess: false)
        let result = await model.addPhoto(data: try image(), title: "Cannot replace this library")
        XCTAssertNil(result); XCTAssertEqual(try Data(contentsOf: manifest), bytes)
        let fresh = PhotoHandoffModel(directory: try directory(), platform: "Mac", allowsCloudAccess: false)
        let invalid = await fresh.addPhoto(data: Data("not a photo".utf8), title: "Invalid")
        XCTAssertNil(invalid); XCTAssertTrue(fresh.photos.isEmpty)
        XCTAssertThrowsError(try PhotoMedia.prepare(Data(count: PhotoMedia.maximumOriginalBytes + 1)))
    }

    func testNormalizedFileSymlinkIsRejectedEvenAfterURLWasCached() async throws {
        let root = try directory()
        let model = PhotoHandoffModel(directory: root, platform: "Mac", allowsCloudAccess: false)
        _ = try await add(model)
        let photo = model.photos[0], url = try XCTUnwrap(model.fileURL(for: model.photos[0]))
        let unrelated = root.appendingPathComponent("unrelated.jpg")
        let original = try Data(contentsOf: url); try original.write(to: unrelated)
        try FileManager.default.removeItem(at: url)
        try FileManager.default.createSymbolicLink(at: url, withDestinationURL: unrelated)
        XCTAssertNil(model.fileURL(for: photo))
        XCTAssertEqual(try Data(contentsOf: unrelated), original)
    }

    func testFailedManifestWriteDoesNotPublishReceipt() async throws {
        let root = try directory(), fake = FakePhotoTransport()
        let model = PhotoHandoffModel(directory: root, platform: "iPhone", transport: fake)
        await model.enable(); let id = try await add(model)
        fake.beforeUploadAcknowledgement = {
            let manifest = root.appendingPathComponent("photos.json")
            try FileManager.default.removeItem(at: manifest)
            try FileManager.default.createDirectory(at: manifest, withIntermediateDirectories: false)
        }
        await model.sendPhoto(id)
        XCTAssertNotNil(model.error)
        XCTAssertEqual(model.photos[0].statusLabel, "Queued for iCloud")
        XCTAssertFalse(model.photos[0].isUploaded)
        XCTAssertNotNil(fake.records[fake.account]?[id])
    }

    func testFutureManifestAppearingWhileOpenIsNeverOverwritten() async throws {
        let root = try directory()
        let model = PhotoHandoffModel(directory: root, platform: "Mac", allowsCloudAccess: false)
        _ = try await add(model)
        let manifest = root.appendingPathComponent("photos.json")
        let bytes = Data("{\"version\":999,\"photos\":[],\"enabled\":false,\"accounts\":[],\"suppressed\":[]}".utf8)
        try bytes.write(to: manifest)
        let second = await model.addPhoto(data: try image(gray: 0.8), title: "Cannot overwrite future library")
        XCTAssertNil(second); XCTAssertEqual(try Data(contentsOf: manifest), bytes)
        XCTAssertEqual(model.photos.count, 1)
    }
}

@MainActor private final class FakePhotoTransport: PhotoHandoffTransport {
    static let ownerA = PhotoAccount(container: "iCloud.com.ethdawg.workbench.preview", environment: "Development", userRecordName: "owner-a")
    static let ownerB = PhotoAccount(container: "iCloud.com.ethdawg.workbench.preview", environment: "Development", userRecordName: "owner-b")
    let configuration = PhotoCloudConfiguration(isConfigured: true)
    var onAccountChange: (@MainActor @Sendable () -> Void)?
    var account = ownerA
    var offline = false, holdUpload = false, failRemoval = false, corruptDownloads = false, hideChangeRecords = false
    var uploadFailure: PhotoHandoffError?
    var pages: [PhotoChangePage] = []
    var records: [PhotoAccount: [UUID: (RemoteHandoffPhoto, Data)]] = [:]
    var uploads: [(UUID, PhotoAccount)] = []
    var downloads = 0, identityCalls = 0, cancellations = 0, changeCalls = 0
    var checkpoint = Data([1])
    var beforeUploadAcknowledgement: (() throws -> Void)?
    private var uploadWaiter: CheckedContinuation<Void, Never>?
    private var startedWaiter: CheckedContinuation<Void, Never>?
    private var uploadStarted = false
    func identity() async throws -> PhotoAccount {
        identityCalls += 1
        if offline { throw URLError(.notConnectedToInternet) }
        return account
    }
    func upload(_ photo: RemoteHandoffPhoto, fileURL: URL, account owner: PhotoAccount) async throws {
        guard !offline, owner == account else { throw PhotoHandoffError.accountChanged }
        if let uploadFailure { throw uploadFailure }
        let bytes = try Data(contentsOf: fileURL)
        uploads.append((photo.id, owner)); uploadStarted = true
        startedWaiter?.resume(); startedWaiter = nil
        if holdUpload { await withCheckedContinuation { uploadWaiter = $0 } }
        // Deliberately noncooperative: an accepted old-owner request can complete
        // after cancellation, but it never writes into the new owner's database.
        records[owner, default: [:]][photo.id] = (photo, bytes)
        try beforeUploadAcknowledgement?()
    }
    func changes(after checkpoint: Data?, account owner: PhotoAccount) async throws -> PhotoChangePage {
        guard !offline, owner == account else { throw PhotoHandoffError.accountChanged }
        changeCalls += 1
        if !pages.isEmpty { return pages.removeFirst() }
        return PhotoChangePage(photos: hideChangeRecords ? [] : (records[owner] ?? [:]).values.map(\.0), checkpoint: self.checkpoint)
    }
    func download(_ photo: RemoteHandoffPhoto, account owner: PhotoAccount) async throws -> Data {
        guard !offline, owner == account else { throw PhotoHandoffError.accountChanged }
        downloads += 1
        if corruptDownloads { return Data([0, 1, 2]) }
        return try XCTUnwrap(records[owner]?[photo.id]?.1)
    }
    func remove(_ id: UUID, account owner: PhotoAccount) async throws {
        guard !offline, owner == account else { throw PhotoHandoffError.accountChanged }
        if failRemoval { throw URLError(.notConnectedToInternet) }
        records[owner]?.removeValue(forKey: id)
    }
    func cancel() { cancellations += 1 }
    func switchAccount(to account: PhotoAccount) { self.account = account; onAccountChange?() }
    func waitForUpload() async {
        if uploadStarted { return }
        await withCheckedContinuation { startedWaiter = $0 }
    }
    func finishUpload() { holdUpload = false; uploadWaiter?.resume(); uploadWaiter = nil }
}
