import AppKit
import Combine
import ImageIO
import UniformTypeIdentifiers

struct SavedPersona: Codable, Identifiable, Equatable {
    var id = UUID()
    var name: String
    var image: String
    var card: PersonaCardStyle? = nil

    func validated() throws -> SavedPersona {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              name.count <= 160 else { throw PersonaError.invalidSettings }
        _ = try PersonaPlacement(image: image).validated()
        _ = try card?.validated()
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

struct PersonaGroup: Codable, Identifiable, Equatable {
    var id = UUID()
    var name: String
    var personaIDs: [UUID] = []
    var suggestedSceneID: UUID? = nil
    var suggestedLogoID: UUID? = nil
}

/// Only these deliberately prepared candidates can appear in live controls.
/// Reconciliation can remove candidates, but never adds or reorders them.
struct PersonaLiveSelection: Equatable {
    let groupID: UUID
    private(set) var candidateIDs: [UUID]
    private(set) var currentID: UUID?
    init(group: PersonaGroup, selectedID: UUID?) {
        groupID = group.id; candidateIDs = group.personaIDs
        currentID = selectedID.flatMap { candidateIDs.contains($0) ? $0 : nil }
    }
    mutating func select(_ id: UUID) {
        guard candidateIDs.contains(id) else { return }
        currentID = id
    }
    mutating func step(_ offset: Int) {
        guard let currentID, let index = candidateIDs.firstIndex(of: currentID), !candidateIDs.isEmpty else { return }
        let destination = (index + offset % candidateIDs.count + candidateIDs.count) % candidateIDs.count
        self.currentID = candidateIDs[destination]
    }
    mutating func reconcile(group: PersonaGroup?, existingIDs: Set<UUID>) {
        guard let group, group.id == groupID else { candidateIDs = []; currentID = nil; return }
        let allowed = Set(group.personaIDs).intersection(existingIDs)
        candidateIDs.removeAll { !allowed.contains($0) }
        if let currentID, !candidateIDs.contains(currentID) { self.currentID = nil }
    }
}

struct PersonaArchive: Codable {
    var version = 2
    var items: [SavedPersona] = []
    var selectedID: UUID?
    var groups: [PersonaGroup] = []
    var activeGroupID: UUID?

    init(version: Int = 2, items: [SavedPersona] = [], selectedID: UUID? = nil,
         groups: [PersonaGroup] = [], activeGroupID: UUID? = nil) {
        self.version = version; self.items = items; self.selectedID = selectedID
        self.groups = groups; self.activeGroupID = activeGroupID
    }
    private enum CodingKeys: String, CodingKey { case version, items, selectedID, groups, activeGroupID }
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        version = try values.decode(Int.self, forKey: .version)
        items = try values.decode([SavedPersona].self, forKey: .items)
        selectedID = try values.decodeIfPresent(UUID.self, forKey: .selectedID)
        groups = try values.decodeIfPresent([PersonaGroup].self, forKey: .groups) ?? []
        activeGroupID = try values.decodeIfPresent(UUID.self, forKey: .activeGroupID)
    }

    func validated() throws -> PersonaArchive {
        guard [1, 2].contains(version), items.count <= 10_000, groups.count <= 1_000,
              Set(items.map(\.id)).count == items.count,
              Set(items.map(\.image)).count == items.count,
              Set(groups.map(\.id)).count == groups.count,
              selectedID == nil || items.contains(where: { $0.id == selectedID }),
              activeGroupID == nil || groups.contains(where: { $0.id == activeGroupID }),
              version != 1 || (groups.isEmpty && activeGroupID == nil && items.allSatisfy { $0.card == nil })
        else { throw PersonaError.invalidSettings }
        _ = try items.map { try $0.validated() }
        let ids = Set(items.map(\.id))
        for group in groups {
            guard !group.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  group.name.count <= 160, group.name.unicodeScalars.allSatisfy({ !CharacterSet.controlCharacters.contains($0) }),
                  group.personaIDs.count <= 1_000, Set(group.personaIDs).count == group.personaIDs.count,
                  Set(group.personaIDs).isSubset(of: ids) else { throw PersonaError.invalidSettings }
        }
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
    @Published private(set) var groups: [PersonaGroup] = []
    @Published private(set) var activeGroupID: UUID?
    @Published private(set) var liveSelection: PersonaLiveSelection?
    @Published var selectedID: UUID? { didSet { if !applyingArchive { select(previous: oldValue) } } }
    @Published var notice: String?
    @Published private(set) var overlayVisible = false
    @Published private(set) var overlayLocked = false
    @Published private(set) var overlayWidth = 0.16
    var onShow: (() -> Void)?
    var selected: SavedPersona? { items.first { $0.id == selectedID } }
    var activeGroup: PersonaGroup? { groups.first { $0.id == activeGroupID } }
    var visibleItems: [SavedPersona] {
        guard let group = activeGroup else { return items }
        let byID = Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0) })
        return group.personaIDs.compactMap { byID[$0] }
    }
    var isReadOnly: Bool { readOnlyReason != nil }
    private var readOnlyReason: String?
    private var libraryData: Data?
    private var overlayData: Data?
    private var overlayState = PersonaOverlayState()
    private var overlay: PersonaOverlayController?
    private var hud: PersonaHUDController?
    private var displayedID: UUID?
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
                items = archive.items; selectedID = archive.selectedID
                groups = archive.groups; activeGroupID = archive.activeGroupID
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

    func renderedImage(for persona: SavedPersona) -> NSImage? {
        guard (try? persona.validated()) != nil, let image = image(named: persona.image) else { return nil }
        guard let card = persona.card else { return image }
        // Include the file revision: NSCache may evict a portrait and AppKit can
        // later reuse its object address for a different image.
        let attributes = try? FileManager.default.attributesOfItem(atPath: root.appendingPathComponent(persona.image).path)
        let revision = (attributes?[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
        let bytes = (attributes?[.size] as? NSNumber)?.intValue ?? 0
        let key = "card|\(persona.image)|\(revision)|\(bytes)|\(card.label)|\(card.background.r)|\(card.background.g)|\(card.background.b)" as NSString
        if let rendered = imageCache.object(forKey: key) { return rendered }
        guard let rendered = try? PersonaCardRenderer.image(portrait: image, style: card) else { return nil }
        imageCache.setObject(rendered, forKey: key, cost: 480 * 600 * 4)
        return rendered
    }
    /// The caller owns any scene/export copy. This never changes the portrait or a scene.
    func renderedPNG(for persona: SavedPersona) throws -> Data {
        _ = try persona.validated()
        guard let image = renderedImage(for: persona) else { throw PersonaError.unreadableImage }
        if persona.card == nil {
            guard let data = try PersonaStorage.read(root.appendingPathComponent(persona.image), maximumBytes: LogoImport.maximumBytes) else { throw PersonaError.unreadableImage }
            return data
        }
        return try PersonaCardRenderer.png(image)
    }

    func importImage(card: PersonaCardStyle? = nil, onSelect: ((SavedPersona) -> Void)? = nil) {
        guard writable() else { return }
        let panel = NSOpenPanel(); panel.allowedContentTypes = LogoImport.contentTypes
        panel.canChooseDirectories = false; panel.allowsMultipleSelection = false
        panel.message = card == nil ? "Choose a finished persona image. Existing transparency is preserved." : "Choose a portrait without baked labels. Workbench keeps the original and adds editable text and colour."
        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url, let self else { return }
            do { let item = try self.addImage(url, card: card); onSelect?(item) }
            catch { self.reportImport(error) }
        }
    }

    func pasteImage(onSelect: ((SavedPersona) -> Void)? = nil) {
        guard writable() else { return }
        do { let item = try add(LogoImport.read(.general), fallbackName: "Pasted persona"); onSelect?(item) }
        catch { reportImport(error) }
    }

    @discardableResult func addImage(_ url: URL, card: PersonaCardStyle? = nil) throws -> SavedPersona {
        try add(LogoImport.read(url), card: card)
    }

    private func add(_ imported: LogoImport.Image, fallbackName: String? = nil, card: PersonaCardStyle? = nil) throws -> SavedPersona {
        guard writable() else { throw PersonaError.invalidSettings }
        let id = UUID(), file = "persona-" + UUID().uuidString + ".png"
        let proposedName = (fallbackName ?? imported.name).trimmingCharacters(in: .whitespacesAndNewlines)
        let item = try SavedPersona(id: id, name: proposedName.isEmpty ? "Persona" : String(proposedName.prefix(160)), image: file, card: card).validated()
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let destination = root.appendingPathComponent(file)
        try imported.png.write(to: destination, options: .atomic)
        do {
            var next = archive; next.items.append(item); next.selectedID = item.id
            if let index = next.groups.firstIndex(where: { $0.id == activeGroupID }) { next.groups[index].personaIDs.append(item.id) }
            try commit(next)
        }
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
            var next = archive; next.items = changed; next.selectedID = selectedID == id ? nil : selectedID
            for index in next.groups.indices { next.groups[index].personaIDs.removeAll { $0 == id } }
            try commit(next)
            // Scenes may still reference this file. Removing a library entry is
            // never permission to delete its image from the shared scene folder.
            notice = "Removed from saved personas. Scenes using the image are unchanged."
        } catch { notice = error.localizedDescription }
    }

    @discardableResult func updateCard(_ id: UUID, style: PersonaCardStyle?) -> Bool {
        guard writable(), let index = items.firstIndex(where: { $0.id == id }) else { return false }
        do {
            var next = archive; next.items[index].card = try style?.validated()
            try commit(next); notice = nil; return true
        } catch { notice = error.localizedDescription; return false }
    }
    @discardableResult func createGroup(name: String, members: [UUID] = []) throws -> UUID {
        guard writable() else { throw PersonaError.invalidSettings }
        let group = PersonaGroup(name: name.trimmingCharacters(in: .whitespacesAndNewlines), personaIDs: members)
        var next = archive; next.groups.append(group); next.activeGroupID = group.id; next.selectedID = members.first
        try commit(next); hideOverlay(); notice = nil; return group.id
    }
    func renameGroup(_ id: UUID, name: String) {
        guard writable(), let index = groups.firstIndex(where: { $0.id == id }) else { return }
        var next = archive; next.groups[index].name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        do { try commit(next); notice = nil } catch { notice = error.localizedDescription }
    }
    func removeGroup(_ id: UUID) {
        guard writable() else { return }
        var next = archive; next.groups.removeAll { $0.id == id }
        if activeGroupID == id { next.activeGroupID = nil; next.selectedID = nil }
        do { try commit(next); notice = "Group removed. Its personas, images and scenes are kept." }
        catch { notice = error.localizedDescription }
    }
    func prepareGroup(_ id: UUID?) {
        guard writable(), id == nil || groups.contains(where: { $0.id == id }) else { return }
        var next = archive; next.activeGroupID = id
        next.selectedID = id.flatMap { target in groups.first { $0.id == target }?.personaIDs.first }
        do { try commit(next); hideOverlay(); notice = nil } catch { notice = error.localizedDescription }
    }
    func setGroupMembers(_ members: [UUID], in id: UUID) {
        guard writable(), let index = groups.firstIndex(where: { $0.id == id }) else { return }
        var next = archive; next.groups[index].personaIDs = members
        if activeGroupID == id, let selectedID, !members.contains(selectedID) { next.selectedID = nil }
        do { try commit(next); notice = nil } catch { notice = error.localizedDescription }
    }
    func moveMember(_ id: UUID, by offset: Int) {
        guard let group = activeGroup, let index = group.personaIDs.firstIndex(of: id),
              group.personaIDs.indices.contains(index + offset) else { return }
        var members = group.personaIDs; members.swapAt(index, index + offset)
        setGroupMembers(members, in: group.id)
    }

    func stepLivePersona(_ offset: Int) {
        guard var next = liveSelection else { return }
        next.step(offset)
        if let id = next.currentID { selectLivePersona(id) }
    }
    func selectLivePersona(_ id: UUID) {
        guard writable(), var session = liveSelection, session.candidateIDs.contains(id),
              let item = items.first(where: { $0.id == id }), renderedImage(for: item) != nil else { return }
        do {
            try commit(items, selection: id)
            session.select(id); liveSelection = session; displayedID = id; refreshOverlay()
        } catch { notice = error.localizedDescription }
    }
    func focusOverlayControls() { hud?.focusControls() }

    func showOverlay() {
        guard let selected, let image = renderedImage(for: selected) else { notice = PersonaError.unreadableImage.localizedDescription; return }
        if let group = activeGroup, !group.personaIDs.contains(selected.id) { notice = "Choose a persona in the prepared group."; return }
        liveSelection = activeGroup.map { PersonaLiveSelection(group: $0, selectedID: selected.id) }
        displayedID = selected.id
        if overlay == nil {
            overlay = PersonaOverlayController()
            overlay?.onPlacementChange = { [weak self] state in self?.updateOverlay(state) }
        }
        let placed = overlay?.show(image: image, name: publicLabel(for: selected), state: overlayState)
        overlayVisible = true
        if let placed { updateOverlay(placed) }
        refreshHUD()
        onShow?()
    }
    func hideOverlay() { overlay?.hide(); hud?.hide(); overlayVisible = false; liveSelection = nil; displayedID = nil }
    func shutdown() { hideOverlay(); overlay?.shutdown(); overlay = nil; hud?.shutdown(); hud = nil; imageCache.removeAllObjects() }

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
        guard let selected = items.first(where: { $0.id == displayedID }), let image = renderedImage(for: selected) else { hideOverlay(); return }
        overlay?.configure(image: image, name: publicLabel(for: selected), state: overlayState)
        refreshHUD()
    }
    private func publicLabel(for persona: SavedPersona) -> String {
        let label = persona.card?.label.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return label.isEmpty ? "Floating persona" : label
    }
    private func refreshHUD() {
        guard overlayVisible, let session = liveSelection, let current = session.currentID else { hud?.hide(); return }
        if hud == nil {
            let controls = PersonaHUDController(root: root)
            controls.onSelect = { [weak self] in self?.selectLivePersona($0) }
            controls.onStep = { [weak self] in self?.stepLivePersona($0) }
            controls.onHide = { [weak self] in self?.hideOverlay() }
            controls.onLock = { [weak self] in self?.setOverlayLocked($0) }
            controls.onSizeChange = { [weak self] delta in guard let self else { return }; self.setOverlayWidth(self.overlayWidth + delta) }
            if let message = controls.notice { notice = message }
            hud = controls
        }
        let candidates = session.candidateIDs.enumerated().compactMap { index, id -> PersonaHUDItem? in
            guard let persona = items.first(where: { $0.id == id }) else { return nil }
            return PersonaHUDItem.make(persona: persona, ordinal: index + 1, image: renderedImage(for: persona))
        }
        hud?.show(items: candidates, selectedID: current, locked: overlayLocked, near: overlay?.window?.frame)
    }
    private var archive: PersonaArchive { PersonaArchive(items: items, selectedID: selectedID, groups: groups, activeGroupID: activeGroupID) }
    private func commit(_ items: [SavedPersona], selection: UUID?) throws {
        var next = archive; next.items = items; next.selectedID = selection; try commit(next)
    }
    private func commit(_ proposed: PersonaArchive) throws {
        let next = try proposed.validated()
        libraryData = try PersonaStorage.write(next, to: libraryURL, expected: libraryData)
        applyingArchive = true
        items = next.items; selectedID = next.selectedID; groups = next.groups; activeGroupID = next.activeGroupID
        applyingArchive = false
        if var session = liveSelection {
            session.reconcile(group: activeGroup, existingIDs: Set(items.map(\.id)))
            liveSelection = session
            if session.currentID == nil { hideOverlay() }
        }
        if let displayedID, !items.contains(where: { $0.id == displayedID }) { hideOverlay() }
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
        if overlayVisible, selectedID != displayedID { hideOverlay() }
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
