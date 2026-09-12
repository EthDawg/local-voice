import AppKit
import Combine
import ImageIO
import UniformTypeIdentifiers

struct SavedPersona: Codable, Identifiable, Equatable {
    var id = UUID()
    var name: String
    var image: String

    func validated() throws -> SavedPersona {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              name.count <= 160 else { throw PersonaError.invalidSettings }
        _ = try PersonaPlacement(image: image).validated()
        return self
    }
}

struct PersonaPlacement: Codable, Equatable {
    var image: String
    var x = 0.98
    var y = 0.02
    var width = 0.16

    func validated() throws -> PersonaPlacement {
        guard PersonaStorage.isImageName(image), [x, y, width].allSatisfy(\.isFinite)
        else { throw PersonaError.invalidSettings }
        var result = self
        result.x = min(1, max(0, x)); result.y = min(1, max(0, y))
        result.width = min(0.40, max(0.06, width))
        return result
    }
}

enum PersonaGeometry {
    /// Normalized travel in unflipped AppKit coordinates; the entire card stays
    /// inside the canvas at both ends of each axis, regardless of aspect ratio.
    static func rect(_ placement: PersonaPlacement, imageSize: CGSize, in size: CGSize) -> CGRect {
        guard [size.width, size.height, imageSize.width, imageSize.height].allSatisfy({ $0.isFinite && $0 > 0 })
        else { return .zero }
        let fraction = placement.width.isFinite ? min(0.40, max(0.06, placement.width)) : 0.16
        let longest = max(imageSize.width, imageSize.height)
        let unit = CGSize(width: imageSize.width / longest, height: imageSize.height / longest)
        let scale = min(size.width * fraction / unit.width, size.height * 0.6 / unit.height)
        let width = unit.width * scale, height = unit.height * scale
        let x = placement.x.isFinite ? min(1, max(0, placement.x)) : 0.98
        let y = placement.y.isFinite ? min(1, max(0, placement.y)) : 0.02
        return CGRect(x: max(0, size.width - width) * x, y: max(0, size.height - height) * y,
                      width: width, height: height)
    }
}

enum PersonaError: LocalizedError {
    case invalidSettings, changedOnDisk, unreadableImage
    var errorDescription: String? {
        switch self {
        case .invalidSettings: return "The saved personas contain unsupported or invalid settings. The original files are unchanged."
        case .changedOnDisk: return "The persona files changed outside this window. Reopen Workbench before saving changes."
        case .unreadableImage: return "This persona image is missing or unreadable. Import the finished image again."
        }
    }
}

struct PersonaArchive: Codable {
    var version = 1
    var items: [SavedPersona] = []
    var selectedID: UUID?

    func validated() throws -> PersonaArchive {
        guard version == 1, items.count <= 10_000,
              Set(items.map(\.id)).count == items.count,
              Set(items.map(\.image)).count == items.count,
              selectedID == nil || items.contains(where: { $0.id == selectedID })
        else { throw PersonaError.invalidSettings }
        _ = try items.map { try $0.validated() }
        return self
    }
}

/// Desktop placement is independent of every scene's PersonaPlacement. Visibility
/// is deliberately absent: a previously shown card never reopens at launch.
struct PersonaOverlayState: Codable, Equatable {
    var version = 1
    var x = 0.98
    var y = 0.02
    var width = 0.16
    var screenID: UInt32?
    var locked = false

    func validated() throws -> PersonaOverlayState {
        guard version == 1 else { throw PersonaError.invalidSettings }
        let placement = try PersonaPlacement(image: "persona.png", x: x, y: y, width: width).validated()
        var result = self
        result.x = placement.x; result.y = placement.y; result.width = placement.width
        return result
    }
}

enum PersonaStorage {
    static func isImageName(_ name: String) -> Bool {
        !name.isEmpty && name.count <= 255 && !name.hasPrefix(".") &&
        !name.contains("/") && !name.contains("\\") && !name.contains("\0") &&
        name == URL(fileURLWithPath: name).lastPathComponent && name.lowercased().hasSuffix(".png")
    }
    static func read(_ url: URL, maximumBytes: Int = 4 * 1024 * 1024) throws -> Data? {
        let manager = FileManager.default
        // lstat semantics also reject broken symlinks rather than treating them
        // as an absent archive and overwriting them.
        let attributes: [FileAttributeKey: Any]
        do { attributes = try manager.attributesOfItem(atPath: url.path) }
        catch {
            let failure = error as NSError
            if failure.domain == NSCocoaErrorDomain && [NSFileNoSuchFileError, NSFileReadNoSuchFileError].contains(failure.code) { return nil }
            throw error
        }
        guard attributes[.type] as? FileAttributeType == .typeRegular,
              let count = attributes[.size] as? NSNumber, count.intValue <= maximumBytes
        else { throw PersonaError.invalidSettings }
        let data = try Data(contentsOf: url)
        guard data.count <= maximumBytes else { throw PersonaError.invalidSettings }
        return data
    }
    static func write<T: Encodable>(_ value: T, to url: URL, expected: Data?) throws -> Data {
        guard try read(url) == expected else { throw PersonaError.changedOnDisk }
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(value)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
        return data
    }
}

/// Like DemoScenes, this UI model is owned and called by StageKit's main-thread
/// coordinator. Keep storage and scene rendering on that same synchronous path.
final class PersonaLibrary: NSObject, ObservableObject {
    let root: URL
    @Published private(set) var items: [SavedPersona] = []
    @Published var selectedID: UUID? { didSet { if !applyingArchive { select(previous: oldValue) } } }
    @Published var notice: String?
    @Published private(set) var overlayVisible = false
    @Published private(set) var overlayLocked = false
    @Published private(set) var overlayWidth = 0.16
    var onShow: (() -> Void)?
    var selected: SavedPersona? { items.first { $0.id == selectedID } }
    var isReadOnly: Bool { readOnlyReason != nil }
    private var readOnlyReason: String?
    private var libraryData: Data?
    private var overlayData: Data?
    private var overlayState = PersonaOverlayState()
    private var overlay: PersonaOverlayController?
    private let imageCache = NSCache<NSString, NSImage>()
    private var applyingArchive = false
    private var libraryURL: URL { root.appendingPathComponent("persona-library.json") }
    private var overlayURL: URL { root.appendingPathComponent("persona-overlay.json") }

    init(root: URL, readOnlyReason: String? = nil) {
        self.root = root; self.readOnlyReason = readOnlyReason
        super.init()
        imageCache.totalCostLimit = 128 * 1024 * 1024
        applyingArchive = true
        defer { applyingArchive = false }
        do {
            libraryData = try PersonaStorage.read(libraryURL)
            if let libraryData {
                let archive = try JSONDecoder().decode(PersonaArchive.self, from: libraryData).validated()
                items = archive.items; selectedID = archive.selectedID ?? items.first?.id
            }
        } catch { self.readOnlyReason = readOnlyReason ?? error.localizedDescription }
        do {
            overlayData = try PersonaStorage.read(overlayURL)
            if let overlayData { overlayState = try JSONDecoder().decode(PersonaOverlayState.self, from: overlayData).validated() }
            overlayWidth = overlayState.width; overlayLocked = overlayState.locked
        } catch { self.readOnlyReason = self.readOnlyReason ?? error.localizedDescription }
        notice = self.readOnlyReason
    }

    func image(named name: String) -> NSImage? {
        guard PersonaStorage.isImageName(name) else { return nil }
        let url = root.appendingPathComponent(name)
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              attributes[.type] as? FileAttributeType == .typeRegular,
              let count = attributes[.size] as? NSNumber, count.intValue <= LogoImport.maximumBytes,
              let date = attributes[.modificationDate] as? Date else { return nil }
        let key = "\(name)|\(count)|\(date.timeIntervalSince1970)" as NSString
        if let cached = imageCache.object(forKey: key) { return cached }
        guard let data = try? PersonaStorage.read(url, maximumBytes: LogoImport.maximumBytes),
              let source = CGImageSourceCreateWithData(data as CFData, nil),
              CGImageSourceGetType(source) as String? == UTType.png.identifier,
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Double,
              let height = properties[kCGImagePropertyPixelHeight] as? Double,
              width > 0, height > 0, width * height <= 50_000_000,
              let bitmap = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: 4096
              ] as CFDictionary) else { return nil }
        let image = NSImage(cgImage: bitmap, size: CGSize(width: bitmap.width, height: bitmap.height))
        imageCache.setObject(image, forKey: key, cost: bitmap.width * bitmap.height * 4)
        return image
    }

    func importImage(onSelect: ((SavedPersona) -> Void)? = nil) {
        guard writable() else { return }
        let panel = NSOpenPanel(); panel.allowedContentTypes = LogoImport.contentTypes
        panel.canChooseDirectories = false; panel.allowsMultipleSelection = false
        panel.message = "Choose a finished persona image. Existing transparency is preserved."
        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url, let self else { return }
            do { let item = try self.addImage(url); onSelect?(item) }
            catch { self.reportImport(error) }
        }
    }

    func pasteImage(onSelect: ((SavedPersona) -> Void)? = nil) {
        guard writable() else { return }
        do { let item = try add(LogoImport.read(.general), fallbackName: "Pasted persona"); onSelect?(item) }
        catch { reportImport(error) }
    }

    @discardableResult func addImage(_ url: URL) throws -> SavedPersona {
        try add(LogoImport.read(url))
    }

    private func add(_ imported: LogoImport.Image, fallbackName: String? = nil) throws -> SavedPersona {
        guard writable() else { throw PersonaError.invalidSettings }
        let id = UUID(), file = "persona-" + UUID().uuidString + ".png"
        let proposedName = (fallbackName ?? imported.name).trimmingCharacters(in: .whitespacesAndNewlines)
        let item = try SavedPersona(id: id, name: proposedName.isEmpty ? "Persona" : String(proposedName.prefix(160)), image: file).validated()
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let destination = root.appendingPathComponent(file)
        try imported.png.write(to: destination, options: .atomic)
        do { try commit(items + [item], selection: item.id) }
        catch { try? FileManager.default.removeItem(at: destination); throw error }
        notice = nil
        return item
    }

    func rename(_ id: UUID, name: String) {
        guard writable(), let index = items.firstIndex(where: { $0.id == id }) else { return }
        var changed = items; changed[index].name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        do { try commit(changed, selection: selectedID); notice = nil } catch { notice = error.localizedDescription }
    }

    func remove(_ id: UUID) {
        guard writable() else { return }
        let changed = items.filter { $0.id != id }
        do {
            try commit(changed, selection: selectedID == id ? changed.first?.id : selectedID)
            // Scenes may still reference this file. Removing a library entry is
            // never permission to delete its image from the shared scene folder.
            notice = "Removed from saved personas. Scenes using the image are unchanged."
        } catch { notice = error.localizedDescription }
    }

    func showOverlay() {
        guard let selected, let image = image(named: selected.image) else { notice = PersonaError.unreadableImage.localizedDescription; return }
        if overlay == nil {
            overlay = PersonaOverlayController()
            overlay?.onPlacementChange = { [weak self] state in self?.updateOverlay(state) }
        }
        let placed = overlay?.show(image: image, name: selected.name, state: overlayState)
        overlayVisible = true
        if let placed { updateOverlay(placed) }
        onShow?()
    }
    func hideOverlay() { overlay?.hide(); overlayVisible = false }
    func shutdown() { hideOverlay(); overlay?.shutdown(); overlay = nil; imageCache.removeAllObjects() }

    func setOverlayLocked(_ locked: Bool) {
        var state = overlayState; state.locked = locked; updateOverlay(state)
    }
    func setOverlayWidth(_ width: Double) {
        guard width.isFinite else { return }
        var state = overlayState; state.width = min(0.40, max(0.06, width)); updateOverlay(state)
    }
    func setOverlayPosition(x: Double, y: Double) {
        guard x.isFinite, y.isFinite else { return }
        var state = overlayState; state.x = min(1, max(0, x)); state.y = min(1, max(0, y)); updateOverlay(state)
    }

    private func updateOverlay(_ state: PersonaOverlayState) {
        guard let valid = try? state.validated() else { return }
        overlayState = valid; overlayLocked = valid.locked; overlayWidth = valid.width
        if !isReadOnly {
            do { overlayData = try PersonaStorage.write(valid, to: overlayURL, expected: overlayData) }
            catch { notice = error.localizedDescription }
        }
        refreshOverlay()
    }
    private func refreshOverlay() {
        guard overlayVisible else { return }
        guard let selected, let image = image(named: selected.image) else { hideOverlay(); return }
        overlay?.configure(image: image, name: selected.name, state: overlayState)
    }
    private func commit(_ items: [SavedPersona], selection: UUID?) throws {
        let archive = try PersonaArchive(items: items, selectedID: selection).validated()
        libraryData = try PersonaStorage.write(archive, to: libraryURL, expected: libraryData)
        applyingArchive = true; self.items = items; selectedID = selection; applyingArchive = false
        refreshOverlay()
    }
    private func select(previous: UUID?) {
        guard selectedID == nil || selected != nil else {
            applyingArchive = true; selectedID = previous; applyingArchive = false; return
        }
        if !isReadOnly {
            do { try commit(items, selection: selectedID) }
            catch {
                applyingArchive = true; selectedID = previous; applyingArchive = false
                notice = error.localizedDescription; return
            }
        }
        refreshOverlay()
    }
    private func writable() -> Bool {
        if let readOnlyReason { notice = readOnlyReason; return false }
        return true
    }
    private func reportImport(_ error: Error) {
        switch error as? LogoImportError {
        case .emptyClipboard: notice = "Copy an image in your browser or an image file in Finder, then paste the persona here."
        case .emptyImage: notice = "This image is completely transparent. Choose a persona with visible artwork."
        case .invalidImage: notice = "Choose a PNG, JPEG, WebP, HEIC, GIF or TIFF persona under 40 MB and 50 megapixels."
        case nil: notice = error.localizedDescription
        }
    }
}
