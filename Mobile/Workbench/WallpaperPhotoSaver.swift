import Combine
import CryptoKit
import Foundation
import ImageIO
import Photos
import UniformTypeIdentifiers

@MainActor
protocol WallpaperPhotoAdding {
    func authorizationStatus() -> PHAuthorizationStatus
    func requestAddAuthorization() async -> PHAuthorizationStatus
    func addPNG(_ data: Data) async throws
}

/// Add-only access never fetches, edits or deletes an existing Photos asset.
@MainActor
final class SystemWallpaperPhotoLibrary: WallpaperPhotoAdding {
    func authorizationStatus() -> PHAuthorizationStatus { PHPhotoLibrary.authorizationStatus(for: .addOnly) }
    func requestAddAuthorization() async -> PHAuthorizationStatus { await PHPhotoLibrary.requestAuthorization(for: .addOnly) }
    func addPNG(_ data: Data) async throws {
        try await PHPhotoLibrary.shared().performChanges {
            let request = PHAssetCreationRequest.forAsset()
            let options = PHAssetResourceCreationOptions()
            options.originalFilename = "Workbench Wallpaper.png"
            options.uniformTypeIdentifier = UTType.png.identifier
            request.addResource(with: .photo, data: data, options: options)
        }
    }
}

enum WallpaperPhotoSaveState: Equatable {
    case idle, requestingPermission, saving, saved, denied, restricted, failed, cancelled, unconfirmed
}

/// One visible save at a time. Success follows Photos' actual completion, not
/// permission approval. A session-local digest prevents repeated taps from
/// creating the same export again; this is not a Photo Library inventory.
@MainActor
final class WallpaperPhotoSaver: ObservableObject {
    @Published private(set) var state = WallpaperPhotoSaveState.idle
    @Published private(set) var message: String?
    private let library: any WallpaperPhotoAdding
    private var lastSavedDigest: SHA256.Digest?

    init(library: (any WallpaperPhotoAdding)? = nil) { self.library = library ?? SystemWallpaperPhotoLibrary() }

    var isBusy: Bool { state == .requestingPermission || state == .saving }

    func imageChanged() {
        guard !isBusy else { return }
        if state == .saved || state == .failed || state == .cancelled { state = .idle; message = nil }
    }

    @discardableResult
    func save(pngData: Data, allowAnotherCopy: Bool = false) async -> Bool {
        guard !isBusy, state != .unconfirmed || allowAnotherCopy else { return false }
        message = nil
        var submitted = false
        do {
            try Task.checkCancellation()
            try Self.validatePNG(pngData)
            let digest = SHA256.hash(data: pngData)
            if !allowAnotherCopy, digest == lastSavedDigest {
                state = .saved
                message = "This version was already saved to Photos."
                return true
            }
            state = .requestingPermission
            var permission = library.authorizationStatus()
            if permission == .notDetermined { permission = await library.requestAddAuthorization() }
            try Task.checkCancellation()
            switch permission {
            case .authorized, .limited: break
            case .denied:
                state = .denied
                message = "Allow Workbench to add photos in Settings, then try again. You can still share this image."
                return false
            case .restricted:
                state = .restricted
                message = "Adding photos is restricted on this device. Your Workbench image is unchanged; Share is still available."
                return false
            case .notDetermined:
                state = .failed
                message = "Photos permission was not completed. Try saving again, or share the image."
                return false
            @unknown default:
                state = .failed
                message = "Photos access is unavailable. Your Workbench image is unchanged; you can share it instead."
                return false
            }
            state = .saving
            submitted = true
            try await library.addPNG(pngData)
            // PhotoKit has no rollback/cancel for an already submitted change.
            // A late cancellation must not turn a confirmed save into a failure
            // that encourages an accidental duplicate.
            lastSavedDigest = digest
            state = .saved
            message = "Saved to Photos."
            return true
        } catch is CancellationError {
            state = submitted ? .unconfirmed : .cancelled
            message = submitted ? "The save could not be confirmed. Check Photos before saving another copy. Your Workbench image is unchanged."
                : "Save cancelled before adding the image. Your Workbench image is unchanged."
            return false
        } catch {
            state = .failed
            message = "Photos could not save this image: \(error.localizedDescription) Your Workbench image is unchanged. Try again or use Share."
            return false
        }
    }

    static func validatePNG(_ data: Data) throws {
        guard !data.isEmpty, data.count <= 64_000_000,
              let source = CGImageSourceCreateWithData(data as CFData, nil),
              CGImageSourceGetType(source) as String? == UTType.png.identifier,
              CGImageSourceGetCount(source) == 1,
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Double,
              let height = properties[kCGImagePropertyPixelHeight] as? Double,
              width.isFinite, height.isFinite, width >= 1, height >= 1, width <= 3840, height <= 3840,
              CGImageSourceCreateThumbnailAtIndex(source, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true,
                  kCGImageSourceThumbnailMaxPixelSize: 32] as CFDictionary) != nil else {
            throw WallpaperPhotoSaveError.invalidPNG
        }
    }
}

private enum WallpaperPhotoSaveError: LocalizedError {
    case invalidPNG
    var errorDescription: String? { "Create a readable PNG no larger than 3840 pixels per edge and 64 MB before saving." }
}
