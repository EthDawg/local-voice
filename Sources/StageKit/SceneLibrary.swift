import AppKit

struct SavedSceneLogo: Codable, Identifiable, Equatable {
    var id = UUID()
    var name: String
    var image: String
    func validated() throws -> SavedSceneLogo {
        _ = try SceneLogo(image: image).validated()
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, name.count <= 160 else { throw SceneError.invalidScene }
        return self
    }
}

struct StarterPreferences: Codable, Equatable {
    var order: [String] = []
    var names: [String: String] = [:]
    var hidden: Set<String> = []
    var visible: [SceneStarter] {
        let known = Dictionary(uniqueKeysWithValues: SceneStarters.all.map { ($0.id, $0) })
        var seen = Set<String>()
        return (order + SceneStarters.all.map(\.id)).compactMap { id in
            guard var value = known[id], seen.insert(id).inserted, !hidden.contains(id) else { return nil }
            if let name = names[id], !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { value.name = String(name.prefix(160)) }
            return value
        }
    }
    mutating func move(_ id: String, by offset: Int) {
        var ids = visible.map(\.id)
        guard let index = ids.firstIndex(of: id), ids.indices.contains(index + offset) else { return }
        ids.swapAt(index, index + offset); order = ids
    }
}

enum SceneLibraryStorage {
    static func read<T: Decodable>(_ type: T.Type, from url: URL, fallback: T) throws -> T {
        guard FileManager.default.fileExists(atPath: url.path) else { return fallback }
        return try JSONDecoder().decode(type, from: Data(contentsOf: url))
    }
    static func write<T: Encodable>(_ value: T, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(value).write(to: url, options: .atomic)
    }
    /// Original native wordmark, with genuine transparency. No stock asset or
    /// image generation is needed for this editable text-based fallback.
    static func textLogo(_ name: String) throws -> Data {
        let text = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, text.count <= 80 else { throw SceneError.invalidScene }
        let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 72, weight: .semibold),
                                                        .foregroundColor: NSColor(deviceWhite: 0.08, alpha: 1)]
        let label = NSAttributedString(string: text, attributes: attributes)
        let size = label.size()
        let image = NSImage(size: CGSize(width: ceil(size.width) + 32, height: ceil(size.height) + 24), flipped: false) { _ in
            label.draw(at: CGPoint(x: 16, y: 12)); return true
        }
        guard let tiff = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff),
              let data = bitmap.representation(using: .png, properties: [:]) else { throw SceneError.invalidImage }
        return data
    }
}
