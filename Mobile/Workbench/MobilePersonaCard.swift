import SwiftUI
import UIKit
import ImageIO
import UniformTypeIdentifiers

struct MobilePersonaStarter: Identifiable, Equatable, Sendable {
    let id: String
    let label: String
}

struct MobilePersonaPortraits: Sendable {
    static let all: [MobilePersonaStarter] = [
        .init(id: "care-lead", label: "Care lead"), .init(id: "field-lead", label: "Field lead"),
        .init(id: "front-desk", label: "Front desk"), .init(id: "operations-lead", label: "Operations lead"),
        .init(id: "logistics-lead", label: "Logistics lead"), .init(id: "care-coordinator", label: "Care coordinator"),
        .init(id: "hospitality-lead", label: "Hospitality lead"), .init(id: "field-technician", label: "Field technician")
    ]
    let directory: URL?
    init(directory: URL? = Bundle.main.resourceURL?.appendingPathComponent("PersonaPortraits", isDirectory: true)) { self.directory = directory }
    func data(for starter: MobilePersonaStarter) throws -> Data {
        guard Self.all.contains(starter), let directory, directory.isFileURL,
              try FileManager.default.attributesOfItem(atPath: directory.path)[.type] as? FileAttributeType == .typeDirectory else { throw MobilePersonaCardError.unavailable }
        return try Self.read(directory.appendingPathComponent(starter.id + ".png"), requiresPNG: true)
    }
    static func read(_ url: URL, requiresPNG: Bool = false) throws -> Data {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        guard attributes[.type] as? FileAttributeType == .typeRegular,
              let size = attributes[.size] as? NSNumber, size.intValue > 0, size.intValue <= SceneAsset.maximumBytes else { throw MobilePersonaCardError.unavailable }
        let handle = try FileHandle(forReadingFrom: url); defer { try? handle.close() }
        let data = try handle.read(upToCount: SceneAsset.maximumBytes + 1) ?? Data()
        try SceneAsset.validate(data, named: SceneAsset.name(for: data))
        if requiresPNG {
            guard let source = CGImageSourceCreateWithData(data as CFData, nil),
                  CGImageSourceGetType(source) as String? == UTType.png.identifier else { throw MobilePersonaCardError.unavailable }
        }
        return data
    }
    static func thumbnail(_ data: Data) throws -> UIImage {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true, kCGImageSourceThumbnailMaxPixelSize: 300,
                kCGImageSourceShouldCacheImmediately: true] as CFDictionary) else { throw MobilePersonaCardError.unavailable }
        return UIImage(cgImage: image)
    }
}

enum MobilePersonaCardError: LocalizedError {
    case unavailable, invalidStyle
    var errorDescription: String? {
        switch self {
        case .unavailable: "This portrait is missing or unreadable. Choose another starter; your existing scene is kept."
        case .invalidStyle: "Use a label of up to 80 characters and a solid background colour."
        }
    }
}

/// UIKit uses a top-left origin. These rects are the flipped equivalents of
/// PersonaCardRenderer on Mac; the stored rendered PNG is the portable fallback.
@MainActor enum MobilePersonaCardRenderer {
    static let size = CGSize(width: 480, height: 600)
    static func normalized(_ style: SceneCardStyle) throws -> SceneCardStyle {
        guard SceneAsset.isName(style.portrait), style.label.count <= 80,
              !style.label.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }),
              [style.red, style.green, style.blue].allSatisfy({ $0.isFinite && (0...1).contains($0) }) else { throw MobilePersonaCardError.invalidStyle }
        var result = style; result.label = style.label.trimmingCharacters(in: .whitespacesAndNewlines); return result
    }
    static func labelUsesBlack(red: Double, green: Double, blue: Double) -> Bool {
        func linear(_ value: Double) -> Double { value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4) }
        let luminance = 0.2126 * linear(red) + 0.7152 * linear(green) + 0.0722 * linear(blue)
        return (luminance + 0.05) / 0.05 >= 1.05 / (luminance + 0.05)
    }
    static func image(portrait: UIImage, style: SceneCardStyle) throws -> UIImage {
        let style = try normalized(style)
        guard portrait.size.width.isFinite, portrait.size.height.isFinite, portrait.size.width > 0, portrait.size.height > 0 else { throw MobilePersonaCardError.unavailable }
        let format = UIGraphicsImageRendererFormat(); format.scale = 1; format.opaque = false; format.preferredRange = .standard
        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            context.cgContext.clear(CGRect(origin: .zero, size: size))
            let outline = UIBezierPath(roundedRect: CGRect(origin: .zero, size: size), cornerRadius: 28)
            outline.addClip(); UIColor(red: style.red, green: style.green, blue: style.blue, alpha: 1).setFill(); outline.fill()
            let footer: CGFloat = style.label.isEmpty ? 0 : 100
            let available = CGSize(width: size.width - 36, height: size.height - footer - 18)
            let scale = min(available.width / portrait.size.width, available.height / portrait.size.height)
            let fitted = CGSize(width: portrait.size.width * scale, height: portrait.size.height * scale)
            context.cgContext.interpolationQuality = .high
            portrait.draw(in: CGRect(x: (size.width - fitted.width) / 2, y: size.height - footer - fitted.height,
                                     width: fitted.width, height: fitted.height))
            if !style.label.isEmpty {
                let paragraph = NSMutableParagraphStyle(); paragraph.alignment = .center; paragraph.lineBreakMode = .byTruncatingTail
                let attributes: [NSAttributedString.Key: Any] = [
                    .font: UIFont.systemFont(ofSize: 29, weight: .semibold),
                    .foregroundColor: labelUsesBlack(red: style.red, green: style.green, blue: style.blue) ? UIColor.black : UIColor.white,
                    .paragraphStyle: paragraph
                ]
                NSAttributedString(string: style.label, attributes: attributes).draw(
                    with: CGRect(x: 20, y: size.height - 12 - 76, width: size.width - 40, height: 76),
                    options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine], context: nil)
            }
        }
    }
}

/// No library link: both the original portrait and finished PNG become owned,
/// immutable scene assets. Subsequent card edits create a new rendered hash.
struct MobilePersonaCardSnapshot {
    let portrait: Data
    let rendered: Data
    let style: SceneCardStyle
    @MainActor init(portrait: Data, label: String, red: Double, green: Double, blue: Double) throws {
        let name = SceneAsset.name(for: portrait); try SceneAsset.validate(portrait, named: name)
        let style = try MobilePersonaCardRenderer.normalized(SceneCardStyle(portrait: name, label: label, red: red, green: green, blue: blue))
        guard let source = UIImage(data: portrait),
              let rendered = try MobilePersonaCardRenderer.image(portrait: source, style: style).pngData() else { throw MobilePersonaCardError.unavailable }
        self.portrait = portrait; self.rendered = rendered; self.style = style
    }
    @MainActor func install(in scenes: SceneLibraryModel, preserving existing: ScenePersonaLayer?) throws -> ScenePersonaLayer {
        let original = try scenes.importAsset(portrait)
        guard original == style.portrait else { throw MobilePersonaCardError.unavailable }
        let image = try scenes.importAsset(rendered)
        var layer = existing ?? ScenePersonaLayer(image: image); layer.image = image; layer.card = style
        return layer
    }
}

struct MobilePersonaCardSheet: View {
    let existing: ScenePersonaLayer?
    let choosingStarter: Bool
    let onApply: (ScenePersonaLayer) throws -> Void
    @EnvironmentObject private var scenes: SceneLibraryModel
    @Environment(\.dismiss) private var dismiss
    @State private var selected: MobilePersonaStarter?
    @State private var thumbnails: [String: UIImage] = [:]
    @State private var portrait: Data?
    @State private var portraitImage: UIImage?
    @State private var portraitHash = ""
    @State private var label = ""
    @State private var red = 0.08
    @State private var green = 0.38
    @State private var blue = 0.31
    @State private var preview: UIImage?
    @State private var loading = true
    @State private var saving = false
    @State private var notice: String?
    @State private var previewError: String?
    @State private var loadGeneration = UUID()
    @State private var activityID = UUID()
    private let portraits = MobilePersonaPortraits()
    private var previewKey: String { "\(portraitHash):\(label):\(red):\(green):\(blue)" }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if choosingStarter { starterChoices }
                    if let preview {
                        Image(uiImage: preview).resizable().scaledToFit().frame(maxWidth: .infinity, maxHeight: 300)
                            .accessibilityLabel(label.isEmpty ? "Persona card preview" : "Persona card preview: \(label)")
                    } else if loading { ProgressView("Opening portraits…").frame(maxWidth: .infinity, minHeight: 160) }
                    if portrait != nil { controls }
                    if let message = notice ?? previewError { Text(message).foregroundStyle(.secondary).accessibilityIdentifier("persona.notice") }
                    Text("This card belongs to this scene. Other placed cards stay unchanged.").font(.footnote).foregroundStyle(.secondary)
                }.padding(20).frame(maxWidth: 720).frame(maxWidth: .infinity)
            }.navigationTitle(choosingStarter ? "Choose a persona" : "Edit persona card").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.disabled(saving) }
                    ToolbarItem(placement: .confirmationAction) { Button("Use in scene") { apply() }.disabled(portrait == nil || loading || saving || previewError != nil) }
                }
        }.interactiveDismissDisabled(saving)
            .task { SceneEditingActivity.shared.update(sessionID: activityID, isDirty: true); await load() }
            .task(id: previewKey) { await renderPreview() }
            .onDisappear { loadGeneration = UUID(); SceneEditingActivity.shared.update(sessionID: activityID, isDirty: false) }
    }
    private var starterChoices: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Choose a portrait, then edit its role label and colour.").foregroundStyle(.secondary)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 125), spacing: 12)], spacing: 12) {
                ForEach(MobilePersonaPortraits.all) { starter in
                    if let image = thumbnails[starter.id] {
                        Button { Task { await select(starter) } } label: {
                            VStack(spacing: 8) {
                                Image(uiImage: image).resizable().scaledToFit().frame(height: 120).accessibilityHidden(true)
                                Text(starter.label).font(.caption).frame(maxWidth: .infinity)
                            }.padding(10).background(selected == starter ? Color.accentColor.opacity(0.13) : Color(uiColor: .secondarySystemGroupedBackground),
                                                      in: RoundedRectangle(cornerRadius: 12))
                                .overlay { RoundedRectangle(cornerRadius: 12).stroke(selected == starter ? Color.accentColor : .clear, lineWidth: 2) }
                        }.buttonStyle(.plain).accessibilityLabel(starter.label)
                            .accessibilityAddTraits(selected == starter ? .isSelected : []).disabled(saving)
                    }
                }
            }
            if !loading, thumbnails.isEmpty { Text("Starter portraits are unavailable in this build. Your existing scene is kept.").foregroundStyle(.secondary) }
        }
    }
    private var controls: some View {
        VStack(alignment: .leading, spacing: 12) {
            TextField("Role label (optional)", text: $label).textFieldStyle(.roundedBorder)
                .accessibilityIdentifier("persona.label").onChange(of: label) { _, value in label = String(value.prefix(80)) }
            ColorPicker("Background colour", selection: Binding(get: { Color(red: red, green: green, blue: blue) }, set: { color in
                var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
                guard UIColor(color).getRed(&r, green: &g, blue: &b, alpha: &a) else { notice = MobilePersonaCardError.invalidStyle.localizedDescription; return }
                red = Double(r); green = Double(g); blue = Double(b)
            }), supportsOpacity: false).accessibilityIdentifier("persona.colour")
        }.disabled(saving)
    }
    private func load() async {
        let token = UUID(); loadGeneration = token; loading = true
        if choosingStarter {
            var results: [String: UIImage] = [:]
            for starter in MobilePersonaPortraits.all {
                guard !Task.isCancelled, loadGeneration == token else { return }
                let source = portraits
                if let thumbnail = try? await Task.detached(priority: .utility, operation: {
                    try MobilePersonaPortraits.thumbnail(source.data(for: starter))
                }).value { results[starter.id] = thumbnail }
            }
            guard !Task.isCancelled, loadGeneration == token else { return }
            thumbnails = results; loading = false
            if results.count < MobilePersonaPortraits.all.count { notice = "Some starter portraits are missing or unreadable in this build." }
        } else {
            do {
                guard let card = existing?.card else { throw MobilePersonaCardError.unavailable }
                let url = try scenes.assetURL(card.portrait)
                let bytes = try await Task.detached(priority: .utility) { try MobilePersonaPortraits.read(url) }.value
                try Task.checkCancellation(); guard loadGeneration == token else { return }
                guard SceneAsset.name(for: bytes) == card.portrait else { throw MobilePersonaCardError.unavailable }
                _ = try MobilePersonaCardRenderer.normalized(card)
                portrait = bytes; portraitHash = card.portrait; portraitImage = UIImage(data: bytes); label = card.label; red = card.red; green = card.green; blue = card.blue; loading = false
            } catch { guard loadGeneration == token else { return }; notice = error.localizedDescription; loading = false }
        }
    }
    private func select(_ starter: MobilePersonaStarter) async {
        let token = UUID(); loadGeneration = token; loading = true
        do {
            let source = portraits
            let bytes = try await Task.detached(priority: .utility) { try source.data(for: starter) }.value
            try Task.checkCancellation(); guard loadGeneration == token else { return }
            selected = starter; portrait = bytes; portraitHash = SceneAsset.name(for: bytes); portraitImage = UIImage(data: bytes); label = starter.label; notice = nil; loading = false
        } catch { guard loadGeneration == token else { return }; notice = error.localizedDescription; loading = false }
    }
    private func renderPreview() async {
        guard let portraitImage else { preview = nil; return }
        do {
            try await Task.sleep(for: .milliseconds(100)); try Task.checkCancellation()
            let style = SceneCardStyle(portrait: portraitHash, label: label, red: red, green: green, blue: blue)
            let image = try MobilePersonaCardRenderer.image(portrait: portraitImage, style: style)
            guard !Task.isCancelled else { return }; preview = image; previewError = nil
        } catch is CancellationError { }
        catch { preview = nil; previewError = error.localizedDescription }
    }
    private func apply() {
        guard let portrait, !saving, !loading else { return }; saving = true
        defer { saving = false }
        do {
            let snapshot = try MobilePersonaCardSnapshot(portrait: portrait, label: label, red: red, green: green, blue: blue)
            let layer = try snapshot.install(in: scenes, preserving: existing)
            try onApply(layer); dismiss()
        } catch { notice = error.localizedDescription }
    }
}
