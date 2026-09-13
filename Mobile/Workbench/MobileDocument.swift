import Foundation

enum MobileImageKind: String, Codable, CaseIterable, Identifiable {
    case markup, backdrop, wallpaper
    var id: String { rawValue }
    var title: String { switch self { case .markup: "Mark up"; case .backdrop: "Backdrops"; case .wallpaper: "Wallpapers" } }
    var symbol: String { switch self { case .markup: "pencil.tip.crop.circle"; case .backdrop: "rectangle.inset.filled"; case .wallpaper: "photo" } }
}

struct MobileText: Codable, Identifiable, Equatable {
    var id = UUID()
    var title: String
    var original: String
    var text: String
    var modified = Date()
    var audioAsset: String?
}

struct MobileImageProject: Codable, Identifiable, Equatable {
    var id = UUID()
    var title: String
    var kind: MobileImageKind
    var asset: String
    var modified = Date()
    var zoom: Double = 1
    /// Normalised crop centre; the renderer clamps this to preserve full coverage.
    var centerX: Double = 0.5
    var centerY: Double = 0.5
    var wallpaperAspect: Double = 0.4615
    var drawing: Data?
    var foregroundAsset: String?
    var logoAsset: String?
    var personaAsset: String?
    var caption: String = ""
    var allAssets: Set<String> { Set([asset, foregroundAsset, logoAsset, personaAsset].compactMap { $0 }) }

    /// Keep the editable project intact when changing or repairing its source image.
    /// Reset only the crop, because a replacement can have different dimensions.
    mutating func replaceBackground(with asset: String) {
        self.asset = asset
        zoom = 1
        centerX = 0.5
        centerY = 0.5
    }
}

struct MobileDocument: Codable, Equatable {
    static let format = "workbench-mobile"
    var format = Self.format
    var version = 1
    var texts: [MobileText] = []
    var images: [MobileImageProject] = []
    var draft = ""
    var draftOriginal = ""
    var replacements: [Replacement] = []
    var readText = ""
    var voiceID = ""
    var readingRate: Float = 0.5

    static func safeAsset(_ name: String) -> Bool {
        !name.isEmpty && name.count < 100 && name != "." && name != ".."
            && name.unicodeScalars.allSatisfy { CharacterSet.alphanumerics.contains($0) || "-_.".unicodeScalars.contains($0) }
    }

    func validated() throws -> Self {
        guard format == Self.format, version == 1 else { throw MobileStoreError.invalid("This saved library needs a different version of Workbench. It has been left untouched.") }
        guard texts.count <= 500, images.count <= 500, draft.count <= 50_000, draftOriginal.count <= 50_000,
              readText.count <= 50_000, replacements.count <= 500,
              readingRate.isFinite, (0...1).contains(readingRate),
              Set(texts.map(\.id)).count == texts.count, Set(images.map(\.id)).count == images.count else {
            throw MobileStoreError.invalid("This library is outside the supported limits. It has been left untouched.")
        }
        for text in texts {
            guard text.title.count <= 200, text.original.count <= 50_000, text.text.count <= 50_000,
                  text.audioAsset.map(Self.safeAsset) ?? true else { throw MobileStoreError.invalid("A saved text is not valid.") }
        }
        for image in images {
            guard image.title.count <= 200, image.caption.count <= 200,
                  image.allAssets.allSatisfy(Self.safeAsset),
                  image.zoom.isFinite, (1...5).contains(image.zoom),
                  image.centerX.isFinite, (0...1).contains(image.centerX),
                  image.centerY.isFinite, (0...1).contains(image.centerY),
                  image.wallpaperAspect.isFinite, (0.4...1.5).contains(image.wallpaperAspect),
                  (image.drawing?.count ?? 0) <= 4_000_000 else { throw MobileStoreError.invalid("A saved image project is not valid.") }
        }
        return self
    }
}

enum MobileStoreError: LocalizedError {
    case invalid(String)
    var errorDescription: String? { if case .invalid(let message) = self { return message }; return nil }
}

struct MobileDocumentStore {
    let directory: URL
    var manifest: URL { directory.appendingPathComponent("library.json") }
    var assets: URL { directory.appendingPathComponent("Assets", isDirectory: true) }
    static let byteLimit = 24_000_000

    func load() throws -> MobileDocument {
        guard FileManager.default.fileExists(atPath: manifest.path) else { return MobileDocument() }
        let size = try manifest.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard size <= Self.byteLimit else { throw MobileStoreError.invalid("This library is too large to open safely. It has been left untouched.") }
        return try JSONDecoder().decode(MobileDocument.self, from: Data(contentsOf: manifest)).validated()
    }

    func save(_ document: MobileDocument) throws {
        let data = try JSONEncoder().encode(document.validated())
        guard data.count <= Self.byteLimit else { throw MobileStoreError.invalid("The library is full. Export some saved work before adding more.") }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try data.write(to: manifest, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }

    func assetURL(_ name: String) -> URL? {
        MobileDocument.safeAsset(name) ? assets.appendingPathComponent(name) : nil
    }

    func importAsset(_ data: Data, suffix: String) throws -> String {
        guard !data.isEmpty, data.count <= 64_000_000, ["jpg", "png", "heic", "image", "caf", "m4a", "wav", "mp3", "audio"].contains(suffix) else {
            throw MobileStoreError.invalid("Choose a non-empty file smaller than 64 MB.")
        }
        try FileManager.default.createDirectory(at: assets, withIntermediateDirectories: true)
        let name = UUID().uuidString + "." + suffix
        try data.write(to: assets.appendingPathComponent(name), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        return name
    }
}
