import AppKit
import CoreImage

enum HandTone: String, Codable, CaseIterable {
    case original, lighter, deeper
    var label: String { rawValue.capitalized }
}

/// Optional photographic layer. It keeps its own aspect ratio; changing device
/// width never stretches fingers or nails. Alternate poses can replace the PNG.
struct SceneHand: Codable, Equatable {
    var image: String
    var scale = 1.0
    var x = 0.0
    var y = 0.0
    var mirrored = false
    var tone: HandTone = .original
    func validated() throws -> SceneHand {
        guard image == URL(fileURLWithPath: image).lastPathComponent, !image.isEmpty,
              !image.hasPrefix("."), !image.contains("/"), !image.contains("\\"),
              [scale, x, y].allSatisfy(\.isFinite) else { throw SceneError.invalidScene }
        var value = self
        value.scale = min(2, max(0.35, scale)); value.x = min(1, max(-1, x)); value.y = min(1, max(-1, y))
        return value
    }
}

enum HandRenderer {
    static func rect(_ hand: SceneHand, imageSize: CGSize, device: CGRect) -> CGRect {
        let height = device.height * 1.36 * hand.scale
        let width = height * imageSize.width / max(1, imageSize.height)
        let anchor = hand.mirrored ? device.minX - width * 0.37 : device.maxX - width * 0.63
        return CGRect(x: anchor + hand.x * device.width, y: device.minY - height * 0.20 + hand.y * device.height,
                      width: width, height: height)
    }
    static func hasTransparency(_ image: NSImage) -> Bool {
        guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return false }
        let size = 64
        var bytes = [UInt8](repeating: 0, count: size * size * 4)
        let valid = bytes.withUnsafeMutableBytes { ptr -> Bool in
            guard let context = CGContext(data: ptr.baseAddress, width: size, height: size, bitsPerComponent: 8, bytesPerRow: size * 4,
                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            context.draw(cg, in: CGRect(x: 0, y: 0, width: size, height: size)); return true
        }
        guard valid else { return false }
        let alpha = stride(from: 3, to: bytes.count, by: 4).map { bytes[$0] }
        return alpha.contains { $0 > 200 } && alpha.filter { $0 < 10 }.count > size * size / 20
    }
    static func toned(_ image: NSImage, tone: HandTone) -> NSImage {
        guard tone != .original, let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return image }
        let input = CIImage(cgImage: cg)
        let output = input.applyingFilter("CIExposureAdjust", parameters: [kCIInputEVKey: tone == .lighter ? 0.5 : -0.65])
        guard let result = CIContext().createCGImage(output, from: input.extent) else { return image }
        return NSImage(cgImage: result, size: image.size)
    }
    static func draw(_ hand: SceneHand, image: NSImage, device: CGRect) {
        let rect = rect(hand, imageSize: image.size, device: device)
        NSGraphicsContext.saveGraphicsState()
        if hand.mirrored {
            let transform = AffineTransform(translationByX: rect.minX + rect.maxX, byY: 0)
            let t = NSAffineTransform(transform: transform); t.scaleX(by: -1, yBy: 1); t.concat()
        }
        image.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1)
        NSGraphicsContext.restoreGraphicsState()
    }
}
