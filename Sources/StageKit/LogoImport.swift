import AppKit
import ImageIO
import UniformTypeIdentifiers

enum LogoImportError: LocalizedError {
    case invalidImage, emptyImage, emptyClipboard

    var errorDescription: String? {
        switch self {
        case .invalidImage:
            return "Choose a PNG, JPEG, WebP, HEIC, GIF or TIFF logo under 40 MB and 50 megapixels."
        case .emptyImage:
            return "This image is completely transparent. Choose a logo with visible artwork."
        case .emptyClipboard:
            return "Copy an image in your browser, or copy an image file in Finder, then paste the logo here."
        }
    }
}

/// Browser downloads and clipboard images share the same native decoder. Keeping
/// one PNG makes the saved logo independent of the download and its file format.
enum LogoImport {
    static let contentTypes: [UTType] = [.png, .jpeg, .webP, .heic, .gif, .tiff]
    static let maximumBytes = 40 * 1024 * 1024
    private static let maximumPixels = 50_000_000.0
    private static let maximumDimension = 4096

    struct Image {
        let png: Data
        let name: String
    }

    static func read(_ url: URL) throws -> Image {
        guard url.isFileURL else { throw LogoImportError.invalidImage }
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? Int.max
        guard size > 0, size <= maximumBytes else { throw LogoImportError.invalidImage }
        let data = try Data(contentsOf: url)
        return Image(png: try normalizedPNG(data), name: url.deletingPathExtension().lastPathComponent)
    }

    static func read(_ pasteboard: NSPasteboard) throws -> Image {
        // A copied Finder file retains its useful customer name. This deliberately
        // ignores website addresses: pasting never starts a network request.
        let files = pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
        for file in files {
            if let image = try? read(file) { return image }
        }
        let types = contentTypes.map { NSPasteboard.PasteboardType($0.identifier) }
        for type in types where pasteboard.types?.contains(type) == true {
            if let data = pasteboard.data(forType: type) {
                return Image(png: try normalizedPNG(data), name: "Pasted logo")
            }
        }
        if let file = files.first { return try read(file) }
        throw LogoImportError.emptyClipboard
    }

    static func normalizedPNG(_ data: Data) throws -> Data {
        guard !data.isEmpty, data.count <= maximumBytes,
              let source = CGImageSourceCreateWithData(data as CFData, nil),
              let type = CGImageSourceGetType(source) as String?,
              contentTypes.contains(where: { $0.identifier == type }),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Double,
              let height = properties[kCGImagePropertyPixelHeight] as? Double,
              width > 0, height > 0, width * height <= maximumPixels,
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: maximumDimension,
                kCGImageSourceShouldCacheImmediately: true
              ] as CFDictionary) else { throw LogoImportError.invalidImage }

        let trimmed = try removingTransparentPadding(image)
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, UTType.png.identifier as CFString, 1, nil)
        else { throw LogoImportError.invalidImage }
        CGImageDestinationAddImage(destination, trimmed, nil)
        guard CGImageDestinationFinalize(destination) else { throw LogoImportError.invalidImage }
        return output as Data
    }

    private static func removingTransparentPadding(_ image: CGImage) throws -> CGImage {
        // Inspect alpha only. White backgrounds, faint shadows and antialiasing
        // remain intact; only completely empty rows and columns can be removed.
        let width = image.width, height = image.height
        let bytesPerRow = width * 4
        guard let context = CGContext(data: nil, width: width, height: height,
                                      bitsPerComponent: 8, bytesPerRow: bytesPerRow,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue),
              let pixels = context.data?.assumingMemoryBound(to: UInt8.self)
        else { throw LogoImportError.invalidImage }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        var minX = width, minY = height, maxX = -1, maxY = -1
        for y in 0..<height {
            for x in 0..<width where pixels[y * bytesPerRow + x * 4 + 3] > 0 {
                minX = min(minX, x); minY = min(minY, y)
                maxX = max(maxX, x); maxY = max(maxY, y)
            }
        }
        guard maxX >= minX, maxY >= minY else { throw LogoImportError.emptyImage }
        if minX == 0, minY == 0, maxX == width - 1, maxY == height - 1 { return image }
        guard let trimmed = image.cropping(to: CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1))
        else { throw LogoImportError.invalidImage }
        return trimmed
    }
}
