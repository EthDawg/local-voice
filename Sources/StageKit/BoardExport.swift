import AppKit

enum BoardExportError: LocalizedError {
    case noBoard, invalidCanvas, renderFailed, clipboardUnavailable
    var errorDescription: String? {
        switch self {
        case .noBoard: return "Open a whiteboard or blackboard to copy or save its image."
        case .invalidCanvas: return "This board cannot be exported because its size or drawing data is invalid."
        case .renderFailed: return "The board image could not be created. Your drawing is unchanged."
        case .clipboardUnavailable: return "The board image could not be copied. Try saving it as a PNG instead."
        }
    }
}

/// An immutable snapshot of our own canvas, never a capture of another window.
/// Ink uses the same top-left coordinates and renderer as AnnotationView.
struct BoardImageExport {
    let style: BoardStyle
    let size: CGSize
    let annotations: [Annotation]
    var scale: CGFloat = 1

    static func background(_ style: BoardStyle) -> NSColor {
        style == .white ? NSColor(srgbRed: 0.975, green: 0.98, blue: 0.99, alpha: 1)
            : NSColor(srgbRed: 0.055, green: 0.07, blue: 0.105, alpha: 1)
    }

    func png() throws -> Data {
        guard size.width.isFinite, size.height.isFinite, size.width >= 1, size.height >= 1,
              size.width <= 32768, size.height <= 32768, scale.isFinite, scale > 0,
              annotations.allSatisfy({ annotation in
                  annotation.width.isFinite && annotation.width > 0 && annotation.width <= 1000 &&
                  annotation.fontSize.isFinite && annotation.fontSize > 0 && annotation.fontSize <= 1000 &&
                  annotation.color.r.isFinite && annotation.color.g.isFinite && annotation.color.b.isFinite &&
                  annotation.points.allSatisfy { $0.x.isFinite && $0.y.isFinite && $0.pressure.isFinite }
              }) else { throw BoardExportError.invalidCanvas }
        // Keep Retina detail without allocating an unbounded bitmap on large displays.
        let outputScale = min(scale, 4, 8192 / size.width, 8192 / size.height,
                              sqrt(32_000_000 / (size.width * size.height)))
        let width = max(1, Int((size.width * outputScale).rounded(.down)))
        let height = max(1, Int((size.height * outputScale).rounded(.down)))
        guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
              let bitmapContext = NSGraphicsContext(bitmapImageRep: bitmap) else { throw BoardExportError.renderFailed }
        let cg = bitmapContext.cgContext
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        cg.translateBy(x: 0, y: CGFloat(height))
        cg.scaleBy(x: CGFloat(width) / size.width, y: -CGFloat(height) / size.height)
        NSGraphicsContext.current = NSGraphicsContext(cgContext: cg, flipped: true)
        let bounds = CGRect(origin: .zero, size: size)
        NSBezierPath(rect: bounds).addClip()
        Self.background(style).setFill(); bounds.fill()
        for annotation in annotations { InkRenderer.draw(annotation) }
        guard let data = bitmap.representation(using: .png, properties: [:]) else { throw BoardExportError.renderFailed }
        return data
    }

    /// Generate first so a rendering failure never clears an existing clipboard.
    func copy(to pasteboard: NSPasteboard = .general) throws {
        let data = try png()
        let item = NSPasteboardItem()
        guard item.setData(data, forType: .png) else { throw BoardExportError.clipboardUnavailable }
        pasteboard.clearContents()
        guard pasteboard.writeObjects([item]) else { throw BoardExportError.clipboardUnavailable }
    }
}
