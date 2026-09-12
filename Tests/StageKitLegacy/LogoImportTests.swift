import AppKit
import ImageIO
import UniformTypeIdentifiers

final class LogoImportTests {
    // Real lossless WebP: an 8 x 6 transparent canvas, with 4 x 3 artwork
    // offset from centre, a half-transparent blue top-left and green bottom-right.
    private let webP = Data(base64Encoded: "UklGRjoAAABXRUJQVlA4TC0AAAAvB0ABEB8gEEjaH3oNAUGR/6PNv4Cg6LrlAuZGg4K2bRiv/IHsAY7of8Cn0wUA")!

    private func encode(_ image: CGImage, type: UTType = .png, properties: [CFString: Any] = [:]) throws -> Data {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, type.identifier as CFString, 1, nil)
        else { throw LogoImportError.invalidImage }
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw LogoImportError.invalidImage }
        return data as Data
    }

    func testWebPAndTransparentPadding() throws {
        let normalized = try LogoImport.normalizedPNG(webP)
        XCTAssertEqual(Array(normalized.prefix(8)), [137, 80, 78, 71, 13, 10, 26, 10])
        let bitmap = NSBitmapImageRep(data: normalized)!
        XCTAssertEqual(bitmap.pixelsWide, 4)
        XCTAssertEqual(bitmap.pixelsHigh, 3)
        let blue = bitmap.colorAt(x: 0, y: 0)!.usingColorSpace(.deviceRGB)!
        XCTAssertGreaterThan(blue.blueComponent, 0.95)
        XCTAssertEqual(Double(blue.alphaComponent), 128.0 / 255.0, accuracy: 0.01)
        let green = bitmap.colorAt(x: 3, y: 2)!.usingColorSpace(.deviceRGB)!
        XCTAssertGreaterThan(green.greenComponent, 0.95)
        XCTAssertEqual(Double(green.alphaComponent), 1, accuracy: 0.001)
        XCTAssertTrue(LogoImport.contentTypes.contains(.webP))

        // Opaque white is real image content, not a transparent margin.
        let context = CGContext(data: nil, width: 10, height: 7, bitsPerComponent: 8, bytesPerRow: 40,
                                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(CGColor(gray: 1, alpha: 1)); context.fill(CGRect(x: 0, y: 0, width: 10, height: 7))
        let opaque = NSBitmapImageRep(data: try LogoImport.normalizedPNG(encode(context.makeImage()!)))!
        XCTAssertEqual(opaque.pixelsWide, 10); XCTAssertEqual(opaque.pixelsHigh, 7)
    }

    func testOrientationAndInvalidImages() throws {
        let source = CGImageSourceCreateWithData(webP as CFData, nil)!
        let image = CGImageSourceCreateImageAtIndex(source, 0, nil)!
        let rotated = try encode(image, type: .tiff, properties: [kCGImagePropertyOrientation: 6])
        let result = NSBitmapImageRep(data: try LogoImport.normalizedPNG(rotated))!
        XCTAssertEqual(result.pixelsWide, 3); XCTAssertEqual(result.pixelsHigh, 4)
        let blue = result.colorAt(x: 2, y: 0)!.usingColorSpace(.deviceRGB)!
        XCTAssertGreaterThan(blue.blueComponent, 0.95)

        XCTAssertThrowsError(try LogoImport.normalizedPNG(Data("This is not an image".utf8)))
        XCTAssertThrowsError(try LogoImport.normalizedPNG(Data()))
        XCTAssertThrowsError(try LogoImport.normalizedPNG(Data(repeating: 0, count: LogoImport.maximumBytes + 1)))
        let empty = CGContext(data: nil, width: 2, height: 2, bitsPerComponent: 8, bytesPerRow: 8,
                              space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        XCTAssertThrowsError(try LogoImport.normalizedPNG(encode(empty.makeImage()!)))

        let wide = CGContext(data: nil, width: 6000, height: 2, bitsPerComponent: 8, bytesPerRow: 24000,
                             space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        wide.setFillColor(CGColor(gray: 0, alpha: 1)); wide.fill(CGRect(x: 0, y: 0, width: 6000, height: 2))
        let bounded = NSBitmapImageRep(data: try LogoImport.normalizedPNG(encode(wide.makeImage()!)))!
        XCTAssertEqual(bounded.pixelsWide, 4096)
        XCTAssertGreaterThan(bounded.pixelsHigh, 0)
    }

    func testPasteImageAndFilePersistence() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("LogoImport-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let background = root.appendingPathComponent("backdrop.png")
        try LogoImport.normalizedPNG(webP).write(to: background)
        let model = DemoScenes(root: root.appendingPathComponent("store"))
        try model.addImage(background)
        let clipboard = NSPasteboard.withUniqueName()
        defer { clipboard.releaseGlobally() }
        clipboard.setData(webP, forType: NSPasteboard.PasteboardType(UTType.webP.identifier))
        model.pasteLogo(from: clipboard)
        XCTAssertNotNil(model.selected?.logo)
        XCTAssertEqual(model.savedLogos.first?.name, "Pasted logo")
        XCTAssertEqual(model.selected?.logo?.image.hasSuffix(".png"), true)

        let source = root.appendingPathComponent("Customer logo.webp")
        try webP.write(to: source)
        clipboard.clearContents(); clipboard.writeObjects([source as NSURL])
        XCTAssertEqual(try LogoImport.read(clipboard).name, "Customer logo")
        model.pasteLogo(from: clipboard)
        XCTAssertEqual(model.savedLogos.count, 1, "Equivalent imports must not duplicate the reusable library")
        let scene = model.selected!
        try FileManager.default.removeItem(at: source)
        let reopened = DemoScenes(root: model.root)
        XCTAssertNotNil(reopened.logoImage(for: scene))

        // The bytes determine the format, even when a download has a poor name.
        let misnamed = root.appendingPathComponent("download.bin")
        try webP.write(to: misnamed)
        XCTAssertEqual(try LogoImport.read(misnamed).png, try LogoImport.normalizedPNG(webP))

        clipboard.clearContents(); clipboard.setString("https://example.com/logo.png", forType: .string)
        model.pasteLogo(from: clipboard)
        XCTAssertEqual(model.selected, scene, "A pasted website address must not replace the saved logo")
        XCTAssertNotNil(model.notice)

        // Browser image copying commonly supplies TIFF rather than the file type.
        let tiff = NSImage(data: try LogoImport.normalizedPNG(webP))!.tiffRepresentation!
        clipboard.clearContents(); clipboard.setData(tiff, forType: .tiff)
        XCTAssertNotNil(NSImage(data: try LogoImport.read(clipboard).png))
    }
}
