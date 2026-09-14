import UIKit
import PencilKit
import ImageIO

enum MobileImageRenderer {
    static func logicalDrawingSize(_ image: CGSize) -> CGSize {
        let scale = 1200 / max(1, max(image.width, image.height))
        return CGSize(width: image.width * scale, height: image.height * scale)
    }

    static func aspect(project: MobileImageProject, background: UIImage) -> CGFloat {
        switch project.kind {
        case .markup: return background.size.width / max(1, background.size.height)
        case .backdrop: return 16 / 9
        case .wallpaper: return CGFloat(project.wallpaperAspect)
        }
    }

    /// Image centre coordinates are normalised in the original image. Clamp the
    /// resulting rectangle, rather than stretching or exposing empty edges.
    static func cropRect(image: CGSize, canvas: CGSize, zoom: Double, centerX: Double, centerY: Double) -> CGRect {
        guard image.width > 0, image.height > 0, canvas.width > 0, canvas.height > 0 else { return .zero }
        let scale = max(canvas.width / image.width, canvas.height / image.height) * CGFloat(min(5, max(1, zoom)))
        let size = CGSize(width: image.width * scale, height: image.height * scale)
        return CGRect(x: min(0, max(canvas.width - size.width, canvas.width / 2 - size.width * CGFloat(centerX))),
                      y: min(0, max(canvas.height - size.height, canvas.height / 2 - size.height * CGFloat(centerY))),
                      width: size.width, height: size.height)
    }

    static func render(project: MobileImageProject, background: UIImage, foreground: UIImage? = nil,
                       logo: UIImage? = nil, persona: UIImage? = nil, maxDimension: CGFloat = 3840) throws -> UIImage {
        let aspect = aspect(project: project, background: background)
        guard aspect.isFinite, aspect > 0, maxDimension.isFinite, maxDimension >= 1,
              background.size.width > 0, background.size.height > 0,
              project.zoom.isFinite, (1...5).contains(project.zoom),
              project.centerX.isFinite, (0...1).contains(project.centerX),
              project.centerY.isFinite, (0...1).contains(project.centerY) else {
            throw MobileStoreError.invalid("This image cannot be rendered with its saved crop.")
        }
        if project.kind == .backdrop {
            guard project.foregroundAsset == nil || foreground != nil,
                  project.logoAsset == nil || logo != nil, project.personaAsset == nil || persona != nil else {
                throw MobileStoreError.invalid("A saved picture, logo or persona is missing. Replace or remove that layer before sharing.")
            }
        }
        let drawing: PKDrawing?
        do { drawing = try project.kind == .markup ? project.drawing.map(PKDrawing.init(data:)) : nil }
        catch { throw MobileStoreError.invalid("The saved drawing could not be read. Your original image is preserved.") }
        let edge = min(3840, maxDimension)
        let size = aspect >= 1 ? CGSize(width: edge, height: max(1, (edge / aspect).rounded()))
            : CGSize(width: max(1, (edge * aspect).rounded()), height: edge)
        let format = UIGraphicsImageRendererFormat(); format.scale = 1; format.opaque = project.kind != .markup
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            draw(project: project, background: background, foreground: foreground, logo: logo, persona: persona,
                 drawing: drawing, size: size)
        }
    }

    static func draw(project: MobileImageProject, background: UIImage, foreground: UIImage? = nil,
                     logo: UIImage? = nil, persona: UIImage? = nil, drawing: PKDrawing? = nil, size: CGSize) {
        let bounds = CGRect(origin: .zero, size: size)
        guard let context = UIGraphicsGetCurrentContext() else { return }
        context.saveGState(); defer { context.restoreGState() }
        context.clip(to: bounds)
        if project.kind == .markup {
            context.clear(bounds)
            background.draw(in: bounds)
            if let drawing {
                let logical = logicalDrawingSize(background.size)
                drawing.image(from: CGRect(origin: .zero, size: logical), scale: size.width / logical.width).draw(in: bounds)
            }
            return
        }
        UIColor.white.setFill(); context.fill(bounds)
        background.draw(in: cropRect(image: background.size, canvas: size, zoom: project.zoom,
                                      centerX: project.centerX, centerY: project.centerY))
        guard project.kind == .backdrop else { return }
        if let foreground {
            let portrait = foreground.size.height > foreground.size.width * 1.2
            let box = CGRect(x: size.width * (portrait ? 0.35 : 0.18), y: size.height * 0.08,
                             width: size.width * (portrait ? 0.30 : 0.64), height: size.height * 0.80)
            let rect = fitted(foreground.size, in: box)
            let padding = size.height * 0.012
            let outer = rect.insetBy(dx: -padding, dy: -padding)
            context.saveGState()
            context.setShadow(offset: CGSize(width: 0, height: size.height * 0.014), blur: size.height * 0.045,
                              color: UIColor.black.withAlphaComponent(0.28).cgColor)
            UIColor(white: 0.07, alpha: 1).setFill()
            UIBezierPath(roundedRect: outer, cornerRadius: portrait ? rect.width * 0.09 : padding).fill()
            context.restoreGState()
            context.saveGState()
            UIBezierPath(roundedRect: rect, cornerRadius: portrait ? rect.width * 0.065 : 0).addClip()
            foreground.draw(in: rect); context.restoreGState()
        }
        if let logo {
            logo.draw(in: fitted(logo.size, in: CGRect(x: size.width * 0.05, y: size.height * 0.055,
                                                     width: size.width * 0.22, height: size.height * 0.13)))
        }
        if let persona {
            let box = CGRect(x: size.width * 0.75, y: size.height * 0.47, width: size.width * 0.20, height: size.height * 0.46)
            let fit = fitted(persona.size, in: box)
            persona.draw(in: CGRect(x: box.maxX - fit.width, y: box.maxY - fit.height, width: fit.width, height: fit.height))
        }
        let caption = project.caption.trimmingCharacters(in: .whitespacesAndNewlines)
        if !caption.isEmpty {
            let paragraph = NSMutableParagraphStyle(); paragraph.lineBreakMode = .byTruncatingTail
            let shadow = NSShadow(); shadow.shadowColor = UIColor.black.withAlphaComponent(0.8)
            shadow.shadowBlurRadius = size.height * 0.008; shadow.shadowOffset = CGSize(width: 0, height: 1)
            (caption as NSString).draw(in: CGRect(x: size.width * 0.05, y: size.height * 0.875,
                                                width: size.width * 0.67, height: size.height * 0.095),
                                      withAttributes: [.font: UIFont.systemFont(ofSize: size.height * 0.042, weight: .semibold),
                                                       .foregroundColor: UIColor.white, .paragraphStyle: paragraph, .shadow: shadow])
        }
    }

    private static func fitted(_ image: CGSize, in rect: CGRect) -> CGRect {
        let scale = min(rect.width / max(1, image.width), rect.height / max(1, image.height))
        let size = CGSize(width: image.width * scale, height: image.height * scale)
        return CGRect(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2, width: size.width, height: size.height)
    }

    /// Small original colour studies, generated locally without downloaded or
    /// customer artwork. The exported image contains no UI or baked-in labels.
    static func starter(_ palette: MobileBackdropPalette, portrait: Bool) -> UIImage {
        let size = portrait ? CGSize(width: 1200, height: 1800) : CGSize(width: 1800, height: 1125)
        let format = UIGraphicsImageRendererFormat(); format.scale = 1; format.opaque = true
        return UIGraphicsImageRenderer(size: size, format: format).image { renderer in
            let context = renderer.cgContext
            let colors = palette.colors.map(\.cgColor) as CFArray
            if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1]) {
                context.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: size.width, y: size.height), options: [])
            }
            UIColor.white.withAlphaComponent(0.08).setFill()
            context.fillEllipse(in: CGRect(x: -size.width * 0.35, y: size.height * 0.25, width: size.width * 1.1, height: size.width * 1.1))
            UIColor.white.withAlphaComponent(0.05).setFill()
            context.fillEllipse(in: CGRect(x: size.width * 0.42, y: -size.height * 0.12, width: size.width, height: size.width))
        }
    }
}

enum MobileBackdropPalette: String, CaseIterable, Identifiable {
    case coast = "Coast", dusk = "Dusk", paper = "Paper", ink = "Ink"
    var id: String { rawValue }
    var colors: [UIColor] {
        switch self {
        case .coast: return [UIColor(red: 0.20, green: 0.52, blue: 0.54, alpha: 1), UIColor(red: 0.04, green: 0.18, blue: 0.28, alpha: 1)]
        case .dusk: return [UIColor(red: 0.65, green: 0.38, blue: 0.38, alpha: 1), UIColor(red: 0.18, green: 0.17, blue: 0.34, alpha: 1)]
        case .paper: return [UIColor(red: 0.92, green: 0.87, blue: 0.77, alpha: 1), UIColor(red: 0.59, green: 0.66, blue: 0.61, alpha: 1)]
        case .ink: return [UIColor(red: 0.22, green: 0.27, blue: 0.36, alpha: 1), UIColor(red: 0.06, green: 0.08, blue: 0.13, alpha: 1)]
        }
    }
}
