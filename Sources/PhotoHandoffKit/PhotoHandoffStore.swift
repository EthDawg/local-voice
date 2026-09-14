import Foundation
import ImageIO
import CoreGraphics
import UniformTypeIdentifiers
import CryptoKit
import Darwin

struct PreparedPhoto: Sendable {
    let jpeg: Data
    let digest: String
    let width: Int
    let height: Int
}

enum PhotoMedia {
    static let maximumOriginalBytes = 64_000_000
    static let maximumTransferBytes = 40_000_000
    static func digest(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }
    static func prepare(_ data: Data) throws -> PreparedPhoto {
        guard !data.isEmpty, data.count <= maximumOriginalBytes,
              let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
              CGImageSourceGetCount(source) == 1,
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Double,
              let height = properties[kCGImagePropertyPixelHeight] as? Double,
              width.isFinite, height.isFinite, width > 0, height > 0, width * height <= 50_000_000,
              let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: 3840, kCGImageSourceShouldCacheImmediately: true
              ] as CFDictionary)
        else { throw PhotoHandoffError.invalid("Choose a readable still image under 64 MB and 50 megapixels.") }
        // A fresh sRGB canvas flattens transparency to white and does not carry
        // source GPS/EXIF dictionaries into the optimized transfer image.
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let canvas = CGContext(data: nil, width: thumbnail.width, height: thumbnail.height,
                bitsPerComponent: 8, bytesPerRow: 0, space: space, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
        else { throw PhotoHandoffError.invalid("This photo could not be prepared.") }
        canvas.setFillColor(CGColor(gray: 1, alpha: 1))
        canvas.fill(CGRect(x: 0, y: 0, width: thumbnail.width, height: thumbnail.height))
        canvas.draw(thumbnail, in: CGRect(x: 0, y: 0, width: thumbnail.width, height: thumbnail.height))
        guard let image = canvas.makeImage() else { throw PhotoHandoffError.invalid("This photo could not be prepared.") }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, UTType.jpeg.identifier as CFString, 1, nil)
        else { throw PhotoHandoffError.invalid("The transfer JPEG could not be created.") }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: 0.88,
                                                       kCGImagePropertyOrientation: 1] as CFDictionary)
        guard CGImageDestinationFinalize(destination), output.length > 0, output.length <= maximumTransferBytes
        else { throw PhotoHandoffError.invalid("This photo is too large to transfer. Choose a smaller image.") }
        let jpeg = output as Data
        return PreparedPhoto(jpeg: jpeg, digest: digest(jpeg), width: image.width, height: image.height)
    }
    static func validate(_ data: Data, against photo: RemoteHandoffPhoto) throws {
        _ = try photo.validated()
        guard data.count == photo.byteCount, digest(data) == photo.digest,
              let source = CGImageSourceCreateWithData(data as CFData, nil), CGImageSourceGetCount(source) == 1,
              CGImageSourceGetType(source) as String? == UTType.jpeg.identifier,
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue == photo.width,
              (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue == photo.height,
              CGImageSourceCreateThumbnailAtIndex(source, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceThumbnailMaxPixelSize: 160] as CFDictionary) != nil
        else { throw PhotoHandoffError.invalid("A downloaded photo failed its size, format or integrity check. Its refresh position was kept for retry.") }
    }
}

struct PhotoReceipt: Codable, Equatable {
    let account: PhotoAccount
    let id: UUID
    let digest: String
}
struct PhotoAccountState: Codable {
    let account: PhotoAccount
    var checkpoint: Data?
    var retryNotBefore: Date?
}
struct PhotoHandoffDocument: Codable {
    var version = 1
    var photos: [HandoffPhoto] = []
    var enabled = false
    var account: PhotoAccount?
    var accounts: [PhotoAccountState] = []
    var suppressed: [PhotoReceipt] = []
    func validated() throws -> Self {
        guard version == 1, photos.count <= 500, accounts.count <= 20, suppressed.count <= 2_000,
              Set(photos.map(\.id)).count == photos.count,
              Set(accounts.map(\.account)).count == accounts.count,
              !enabled || account != nil
        else { throw PhotoHandoffError.invalid("The photo library is unsupported or full. Its original files are preserved.") }
        try account?.validate()
        for photo in photos {
            _ = try photo.remote.validated(); try photo.account?.validate()
            guard photo.disposition == .local || photo.account != nil else {
                throw PhotoHandoffError.invalid("A queued photo has no account owner. Its original files are preserved.")
            }
        }
        for state in accounts {
            try state.account.validate()
            guard (state.checkpoint?.count ?? 0) <= 512_000,
                  state.retryNotBefore?.timeIntervalSince1970.isFinite ?? true else {
                throw PhotoHandoffError.invalid("The saved iCloud refresh state is not readable.")
            }
        }
        for receipt in suppressed { try receipt.account.validate() }
        return self
    }
}

struct PhotoHandoffStore: Sendable {
    let directory: URL
    private var manifest: URL { directory.appendingPathComponent("photos.json") }
    private var media: URL { directory.appendingPathComponent("Photos", isDirectory: true) }
    func load() throws -> PhotoHandoffDocument {
        if try exists(directory) { try requireDirectory(directory) }
        guard try exists(manifest) else { return PhotoHandoffDocument() }
        return try JSONDecoder().decode(PhotoHandoffDocument.self, from: Self.read(manifest, limit: 2_000_000)).validated()
    }
    func save(_ document: PhotoHandoffDocument) throws {
        let data = try JSONEncoder().encode(document.validated())
        guard data.count <= 2_000_000 else { throw PhotoHandoffError.invalid("The photo library is full. Existing photos are preserved.") }
        try makeDirectory(directory)
        if try exists(manifest) {
            _ = try JSONDecoder().decode(PhotoHandoffDocument.self, from: Self.read(manifest, limit: 2_000_000)).validated()
        }
        try data.write(to: manifest, options: .atomic)
    }
    func insert(_ photo: RemoteHandoffPhoto, jpeg: Data, original: Data?) throws {
        try PhotoMedia.validate(jpeg, against: photo)
        guard original.map({ !$0.isEmpty && $0.count <= PhotoMedia.maximumOriginalBytes }) ?? true else {
            throw PhotoHandoffError.invalid("The original photo is outside the supported size limit.")
        }
        try makeDirectory(directory); try makeDirectory(media)
        let destination = media.appendingPathComponent(photo.id.uuidString, isDirectory: true)
        if try exists(destination) {
            try requireDirectory(destination)
            try PhotoMedia.validate(Self.read(destination.appendingPathComponent("image.jpg"), limit: PhotoMedia.maximumTransferBytes), against: photo)
            return
        }
        let staging = media.appendingPathComponent(".incoming-" + UUID().uuidString, isDirectory: true)
        try makeDirectory(staging)
        defer { try? FileManager.default.removeItem(at: staging) }
        try jpeg.write(to: staging.appendingPathComponent("image.jpg"), options: .atomic)
        if let original { try original.write(to: staging.appendingPathComponent("original.bin"), options: .atomic) }
        try FileManager.default.moveItem(at: staging, to: destination)
    }
    /// Only the derived JPEG may be repaired. The immutable original and its
    /// directory are kept; neither a symlink nor a directory is followed.
    func repair(_ photo: HandoffPhoto, jpeg: Data) throws {
        try PhotoMedia.validate(jpeg, against: photo.remote)
        try requireDirectory(directory); try requireDirectory(media)
        let folder = media.appendingPathComponent(photo.id.uuidString, isDirectory: true)
        if try exists(folder) { try requireDirectory(folder) }
        else { try makeDirectory(folder) }
        let destination = folder.appendingPathComponent("image.jpg")
        if try exists(destination) {
            let attributes = try FileManager.default.attributesOfItem(atPath: destination.path)
            guard attributes[.type] as? FileAttributeType == .typeRegular else {
                throw PhotoHandoffError.invalid("The saved photo path is not a regular file. Its original is preserved.")
            }
        }
        try jpeg.write(to: destination, options: .atomic)
    }
    func fileURL(_ photo: HandoffPhoto) throws -> URL {
        let url = try candidateURL(photo)
        try PhotoMedia.validate(Self.read(url, limit: PhotoMedia.maximumTransferBytes), against: photo.remote)
        return url
    }
    func candidateURL(_ photo: HandoffPhoto) throws -> URL {
        try requireDirectory(directory); try requireDirectory(media)
        let folder = media.appendingPathComponent(photo.id.uuidString, isDirectory: true)
        try requireDirectory(folder)
        let url = folder.appendingPathComponent("image.jpg")
        let values = try FileManager.default.attributesOfItem(atPath: url.path)
        guard values[.type] as? FileAttributeType == .typeRegular,
              (values[.size] as? NSNumber)?.intValue == photo.byteCount else {
            throw PhotoHandoffError.invalid("The saved photo is missing or changed.")
        }
        return url
    }
    func removeFiles(_ id: UUID) throws {
        try requireDirectory(directory); try requireDirectory(media)
        let folder = media.appendingPathComponent(id.uuidString, isDirectory: true)
        guard try exists(folder) else { return }
        try requireDirectory(folder)
        // This directory has a fixed UUID name and contains only owned snapshots.
        try FileManager.default.removeItem(at: folder)
    }
    static func read(_ url: URL, limit: Int) throws -> Data {
        let descriptor = open(url.path, O_RDONLY | O_NOFOLLOW)
        guard descriptor >= 0 else { throw CocoaError(.fileReadNoPermission) }
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        defer { try? handle.close() }
        var info = stat()
        guard fstat(descriptor, &info) == 0, (info.st_mode & S_IFMT) == S_IFREG,
              info.st_size >= 0, info.st_size <= limit else { throw PhotoHandoffError.invalid("A photo file is not a regular file within the supported size limit.") }
        var output = Data()
        while output.count <= limit {
            guard let chunk = try handle.read(upToCount: min(1_000_000, limit + 1 - output.count)), !chunk.isEmpty else { break }
            output.append(chunk)
        }
        guard output.count <= limit else { throw PhotoHandoffError.invalid("A photo file exceeded its size limit.") }
        return output
    }
    private func exists(_ url: URL) throws -> Bool {
        do { _ = try FileManager.default.attributesOfItem(atPath: url.path); return true }
        catch let error as CocoaError where error.code == .fileNoSuchFile || error.code == .fileReadNoSuchFile { return false }
    }
    private func requireDirectory(_ url: URL) throws {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        guard attributes[.type] as? FileAttributeType == .typeDirectory else { throw PhotoHandoffError.invalid("The photo storage location is not an owned directory.") }
    }
    private func makeDirectory(_ url: URL) throws {
        if try exists(url) { try requireDirectory(url) }
        else { try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true) }
    }
}
