import Photos
import UIKit
import XCTest
@testable import WorkbenchMobile

@MainActor
private final class WallpaperPhotoLibraryFixture: WallpaperPhotoAdding {
    var permission = PHAuthorizationStatus.notDetermined
    var requestedPermission = PHAuthorizationStatus.authorized
    var requestCount = 0
    var addCount = 0
    var committed: [Data] = []
    var failure: Error?
    var waitForPermission = false
    var waitForCommit = false
    var onPermission: (() -> Void)?
    var onCommit: (() -> Void)?
    private var permissionContinuation: CheckedContinuation<Void, Never>?
    private var commitContinuation: CheckedContinuation<Void, Never>?

    func authorizationStatus() -> PHAuthorizationStatus { permission }
    func requestAddAuthorization() async -> PHAuthorizationStatus {
        requestCount += 1
        if waitForPermission {
            await withCheckedContinuation { permissionContinuation = $0; onPermission?() }
        }
        permission = requestedPermission
        return permission
    }
    func addPNG(_ data: Data) async throws {
        addCount += 1
        if waitForCommit {
            await withCheckedContinuation { commitContinuation = $0; onCommit?() }
        }
        if let failure { throw failure }
        committed.append(data)
    }
    func finishPermission() { permissionContinuation?.resume(); permissionContinuation = nil }
    func finishCommit() { commitContinuation?.resume(); commitContinuation = nil }
}

@MainActor
final class WallpaperPhotoSaverTests: XCTestCase {
    private func image(size: CGSize = CGSize(width: 12, height: 18)) -> UIImage {
        let format = UIGraphicsImageRendererFormat(); format.scale = 1; format.opaque = true
        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            UIColor.systemTeal.setFill(); context.fill(CGRect(origin: .zero, size: size))
            UIColor.white.setFill(); context.fill(CGRect(x: 0, y: 0, width: size.width / 2, height: size.height / 2))
        }
    }

    func testPermissionDenialDoesNotAddAndCanRetryAfterSettingsChange() async throws {
        let library = WallpaperPhotoLibraryFixture(); library.requestedPermission = .denied
        let saver = WallpaperPhotoSaver(library: library)
        let data = try XCTUnwrap(image().pngData())
        let denied = await saver.save(pngData: data)
        XCTAssertFalse(denied)
        XCTAssertEqual(saver.state, .denied)
        XCTAssertFalse(saver.isBusy)
        XCTAssertEqual(library.requestCount, 1)
        XCTAssertEqual(library.addCount, 0)
        XCTAssertTrue(saver.message?.contains("Settings") == true)

        library.permission = .authorized
        let saved = await saver.save(pngData: data)
        XCTAssertTrue(saved)
        XCTAssertEqual(library.requestCount, 1, "A granted add-only permission must not prompt again")
        XCTAssertEqual(library.committed, [data])
        XCTAssertEqual(saver.state, .saved)
    }

    func testRestrictedPermissionNeverRequestsOrWrites() async throws {
        let library = WallpaperPhotoLibraryFixture(); library.permission = .restricted
        let saver = WallpaperPhotoSaver(library: library)
        let saved = await saver.save(pngData: try XCTUnwrap(image().pngData()))
        XCTAssertFalse(saved)
        XCTAssertEqual(saver.state, .restricted)
        XCTAssertEqual(library.requestCount, 0)
        XCTAssertEqual(library.addCount, 0)
        XCTAssertTrue(saver.message?.contains("Share") == true)
    }

    func testConcurrentSaveAndRepeatedIdenticalExportDoNotCreateDuplicates() async throws {
        let library = WallpaperPhotoLibraryFixture(); library.permission = .authorized; library.waitForCommit = true
        let started = expectation(description: "Photo change submitted")
        library.onCommit = { started.fulfill() }
        let saver = WallpaperPhotoSaver(library: library)
        let data = try XCTUnwrap(image().pngData())
        let operation = Task { await saver.save(pngData: data) }
        await fulfillment(of: [started], timeout: 5)
        XCTAssertTrue(saver.isBusy)
        XCTAssertEqual(saver.state, .saving)
        XCTAssertNil(saver.message, "Permission and submission are not success receipts")
        let duplicate = await saver.save(pngData: data)
        XCTAssertFalse(duplicate)
        XCTAssertEqual(library.addCount, 1)
        saver.imageChanged()
        XCTAssertEqual(saver.state, .saving, "Editor updates cannot release the busy guard")
        library.finishCommit()
        let result = await operation.value
        XCTAssertTrue(result)
        XCTAssertEqual(library.committed, [data])
        saver.imageChanged()
        let repeatResult = await saver.save(pngData: data)
        XCTAssertTrue(repeatResult)
        XCTAssertEqual(library.addCount, 1)
        XCTAssertTrue(saver.message?.contains("already saved") == true)
        library.waitForCommit = false
        let deliberateCopy = await saver.save(pngData: data, allowAnotherCopy: true)
        XCTAssertTrue(deliberateCopy)
        XCTAssertEqual(library.committed, [data, data])
    }

    func testFailedPhotoChangeDoesNotClaimSuccessOrRetryAutomatically() async throws {
        let library = WallpaperPhotoLibraryFixture(); library.permission = .authorized
        library.failure = NSError(domain: "WallpaperPhotoFixture", code: 11, userInfo: [NSLocalizedDescriptionKey: "Not enough storage."])
        let saver = WallpaperPhotoSaver(library: library)
        let data = try XCTUnwrap(image().pngData())
        let failed = await saver.save(pngData: data)
        XCTAssertFalse(failed)
        XCTAssertEqual(saver.state, .failed)
        XCTAssertFalse(saver.isBusy)
        XCTAssertEqual(library.addCount, 1)
        XCTAssertTrue(library.committed.isEmpty)
        XCTAssertTrue(saver.message?.contains("Not enough storage") == true)
        library.failure = nil
        let retry = await saver.save(pngData: data)
        XCTAssertTrue(retry)
        XCTAssertEqual(library.committed, [data])
    }

    func testInvalidOrOversizedImageIsRejectedBeforePermission() async throws {
        let library = WallpaperPhotoLibraryFixture()
        let saver = WallpaperPhotoSaver(library: library)
        let inputs = [Data(), Data("not an image".utf8), try XCTUnwrap(image().jpegData(compressionQuality: 1)), try XCTUnwrap(image(size: CGSize(width: 3841, height: 1)).pngData())]
        for data in inputs {
            let result = await saver.save(pngData: data)
            XCTAssertFalse(result)
            XCTAssertEqual(saver.state, .failed)
        }
        XCTAssertEqual(library.requestCount, 0)
        XCTAssertEqual(library.addCount, 0)
    }

    func testCancellationBeforePhotoChangeNeverAddsImage() async throws {
        let library = WallpaperPhotoLibraryFixture(); library.waitForPermission = true
        let started = expectation(description: "Permission requested")
        library.onPermission = { started.fulfill() }
        let saver = WallpaperPhotoSaver(library: library)
        let data = try XCTUnwrap(image().pngData())
        let operation = Task { await saver.save(pngData: data) }
        await fulfillment(of: [started], timeout: 5)
        operation.cancel(); library.finishPermission()
        let result = await operation.value
        XCTAssertFalse(result)
        XCTAssertEqual(saver.state, .cancelled)
        XCTAssertEqual(library.addCount, 0)
    }

    func testCancellationAfterSubmissionDoesNotHideConfirmedSuccess() async throws {
        let library = WallpaperPhotoLibraryFixture(); library.permission = .authorized; library.waitForCommit = true
        let started = expectation(description: "Photo change submitted")
        library.onCommit = { started.fulfill() }
        let saver = WallpaperPhotoSaver(library: library)
        let data = try XCTUnwrap(image().pngData())
        let operation = Task { await saver.save(pngData: data) }
        await fulfillment(of: [started], timeout: 5)
        operation.cancel(); library.finishCommit()
        let result = await operation.value
        XCTAssertTrue(result)
        XCTAssertEqual(saver.state, .saved)
        XCTAssertEqual(library.committed, [data])
    }

    func testUnconfirmedCancellationRequiresDeliberateAnotherCopy() async throws {
        let library = WallpaperPhotoLibraryFixture(); library.permission = .authorized; library.failure = CancellationError()
        let saver = WallpaperPhotoSaver(library: library)
        let data = try XCTUnwrap(image().pngData())
        let result = await saver.save(pngData: data)
        XCTAssertFalse(result)
        XCTAssertEqual(saver.state, .unconfirmed)
        XCTAssertTrue(saver.message?.contains("Check Photos") == true)
        let automaticRetry = await saver.save(pngData: data)
        XCTAssertFalse(automaticRetry)
        XCTAssertEqual(library.addCount, 1)
    }

    func testSavedPNGRetainsExactCropAndLeavesEditorAndOriginalUnchanged() async throws {
        let originalImage = image()
        let originalBytes = try XCTUnwrap(originalImage.pngData())
        var project = MobileImageProject(title: "Synthetic wallpaper", kind: .wallpaper, asset: "original.png")
        project.zoom = 1.7; project.centerX = 0.3; project.centerY = 0.7; project.wallpaperAspect = 0.6
        let before = project
        let rendered = try MobileImageRenderer.render(project: project, background: originalImage, maxDimension: 48)
        let png = try XCTUnwrap(rendered.pngData())
        let library = WallpaperPhotoLibraryFixture(); library.permission = .authorized
        let saver = WallpaperPhotoSaver(library: library)
        let result = await saver.save(pngData: png)
        XCTAssertTrue(result)
        XCTAssertEqual(project, before)
        XCTAssertEqual(originalImage.pngData(), originalBytes)
        XCTAssertEqual(library.committed, [png])
        XCTAssertEqual(UIImage(data: png)?.size, CGSize(width: 29, height: 48))
    }
}
