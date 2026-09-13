import AppKit
import Combine

/// Sanitized presentation data only. There is no group name, private library
/// name, or unfiltered library reference in this controller's input.
struct PersonaHUDItem {
    let id: UUID
    let label: String
    let image: NSImage?
    static func make(persona: SavedPersona, ordinal: Int, image: NSImage?) -> Self {
        let label = persona.card?.label.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return Self(id: persona.id, label: label.isEmpty ? "Persona \(ordinal)" : label, image: image)
    }
}

private struct PersonaHUDPlacement: Codable {
    var version = 1
    var position = PresentationControlPlacement(anchor: .bottom)
    var screenID: UInt32?
    func validated() throws -> Self {
        guard version == 1 else { throw PersonaError.invalidSettings }
        var copy = self; copy.position = try position.validated(); return copy
    }
}

private final class PersonaHUDPanel: NSPanel {
    var keyboardMode = false
    override var canBecomeKey: Bool { keyboardMode }
    override var canBecomeMain: Bool { false }
    override func resignKey() { super.resignKey(); keyboardMode = false }
    override func cancelOperation(_ sender: Any?) { resignKey() }
}

final class PersonaHUDController: NSWindowController {
    var onSelect: ((UUID) -> Void)?
    var onStep: ((Int) -> Void)?
    var onHide: (() -> Void)?
    var onLock: ((Bool) -> Void)?
    var onSizeChange: ((Double) -> Void)?
    private(set) var notice: String?
    private let picker = NSPopUpButton(frame: .zero, pullsDown: false)
    private let options = NSPopUpButton(frame: .zero, pullsDown: true)
    private let previous = NSButton()
    private let next = NSButton()
    private let dismiss = NSButton()
    private let dragHandle = PersonaHUDDragHandle()
    private var locked = false
    private var placement = PersonaHUDPlacement()
    private var savedData: Data?
    private let url: URL
    private var storageBlocked = false
    private var screens: AnyCancellable?
    private var guides: FloatingControlGuideController?

    init(root: URL) {
        url = root.appendingPathComponent("persona-controls.json")
        let panel = PersonaHUDPanel(contentRect: CGRect(x: 0, y: 0, width: 332, height: 44),
            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        super.init(window: panel)
        do {
            savedData = try PersonaStorage.read(url)
            if let savedData { placement = try JSONDecoder().decode(PersonaHUDPlacement.self, from: savedData).validated() }
        } catch { storageBlocked = true; notice = "The previous persona control position is preserved. This session uses a temporary position." }
        panel.title = "Persona controls"; panel.isFloatingPanel = true; panel.level = .floating
        panel.isOpaque = false; panel.backgroundColor = .clear; panel.hasShadow = true
        panel.hidesOnDeactivate = false; panel.becomesKeyOnlyIfNeeded = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        let material = NSVisualEffectView(frame: panel.contentView?.bounds ?? .zero)
        material.material = .popover; material.blendingMode = .behindWindow; material.state = .active
        material.wantsLayer = true; material.layer?.cornerRadius = 12; material.layer?.masksToBounds = true
        panel.contentView = material
        configureButton(previous, symbol: "chevron.left", label: "Previous persona in prepared group", action: #selector(previousPersona))
        configureButton(next, symbol: "chevron.right", label: "Next persona in prepared group", action: #selector(nextPersona))
        configureButton(dismiss, symbol: "xmark", label: "Hide persona and controls", action: #selector(hidePersona))
        picker.target = self; picker.action = #selector(choosePersona)
        picker.setAccessibilityLabel("Choose a persona in the prepared group")
        picker.cell?.lineBreakMode = .byTruncatingTail
        options.setAccessibilityLabel("Persona options")
        let row = NSStackView(views: [dragHandle, previous, picker, next, options, dismiss])
        row.orientation = .horizontal; row.spacing = 4; row.alignment = .centerY
        row.translatesAutoresizingMaskIntoConstraints = false; material.addSubview(row)
        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo: material.leadingAnchor, constant: 7),
            row.trailingAnchor.constraint(equalTo: material.trailingAnchor, constant: -7),
            row.centerYAnchor.constraint(equalTo: material.centerYAnchor),
            dragHandle.widthAnchor.constraint(equalToConstant: 22), dragHandle.heightAnchor.constraint(equalToConstant: 32),
            picker.widthAnchor.constraint(equalToConstant: 154), picker.heightAnchor.constraint(greaterThanOrEqualToConstant: 30),
            options.widthAnchor.constraint(equalToConstant: 32), options.heightAnchor.constraint(greaterThanOrEqualToConstant: 30)
        ])
        dragHandle.onDrag = { [weak self] in self?.previewDrag() }
        dragHandle.onEnd = { [weak self] in self?.finishDrag() }
        screens = NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)
            .receive(on: RunLoop.main).sink { [weak self] _ in
                guard let self else { return }; self.hideGuides(); self.dragHandle.cancel()
                if self.window?.isVisible == true { self.position(near: nil) }
            }
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func show(items: [PersonaHUDItem], selectedID: UUID, locked: Bool, near artwork: CGRect?) {
        guard !items.isEmpty, items.contains(where: { $0.id == selectedID }) else { hide(); return }
        self.locked = locked
        picker.removeAllItems()
        for item in items {
            let menuItem = NSMenuItem(title: item.label, action: nil, keyEquivalent: "")
            menuItem.representedObject = item.id
            if let image = item.image?.copy() as? NSImage { image.size = CGSize(width: 28, height: 28); menuItem.image = image }
            picker.menu?.addItem(menuItem)
        }
        if let index = items.firstIndex(where: { $0.id == selectedID }) { picker.selectItem(at: index) }
        previous.isEnabled = items.count > 1; next.isEnabled = items.count > 1
        picker.setAccessibilityHelp("Only the prepared group's \(items.count) personas are available.")
        rebuildOptions()
        if window?.isVisible != true { position(near: artwork); window?.orderFrontRegardless() }
    }
    func hide() {
        picker.menu?.cancelTracking(); options.menu?.cancelTracking()
        dragHandle.cancel(); hideGuides(); window?.orderOut(nil)
        (window as? PersonaHUDPanel)?.keyboardMode = false
    }
    func shutdown() {
        hide(); screens = nil
        MainActor.assumeIsolated { guides?.shutdown() }; guides = nil
        onSelect = nil; onStep = nil; onHide = nil; onLock = nil; onSizeChange = nil
    }
    /// Called only through an explicit keyboard-access control in preparation.
    func focusControls() {
        guard let panel = window as? PersonaHUDPanel, panel.isVisible else { return }
        panel.keyboardMode = true; panel.makeKey(); panel.makeFirstResponder(picker)
    }

    private func configureButton(_ button: NSButton, symbol: String, label: String, action: Selector) {
        button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        button.imagePosition = .imageOnly; button.bezelStyle = .regularSquare; button.isBordered = false
        button.target = self; button.action = action; button.toolTip = label; button.setAccessibilityLabel(label)
        button.widthAnchor.constraint(equalToConstant: 30).isActive = true
        button.heightAnchor.constraint(equalToConstant: 32).isActive = true
    }
    private func rebuildOptions() {
        options.removeAllItems(); options.addItem(withTitle: "•••")
        let lock = NSMenuItem(title: "Lock artwork · clicks pass through", action: #selector(toggleLock), keyEquivalent: "")
        lock.target = self; lock.state = locked ? .on : .off; options.menu?.addItem(lock)
        for (title, delta) in [("Smaller persona", -0.02), ("Larger persona", 0.02)] {
            let item = NSMenuItem(title: title, action: #selector(changeSize(_:)), keyEquivalent: "")
            item.target = self; item.representedObject = delta; options.menu?.addItem(item)
        }
        let positions = NSMenu(title: "Control position")
        for anchor in FloatingControlAnchor.allCases {
            let item = NSMenuItem(title: anchor.title, action: #selector(choosePosition(_:)), keyEquivalent: "")
            item.target = self; item.representedObject = anchor.rawValue
            item.state = placement.position.anchor == anchor ? .on : .off; positions.addItem(item)
        }
        let menuItem = NSMenuItem(title: "Control position", action: nil, keyEquivalent: "")
        menuItem.submenu = positions; options.menu?.addItem(menuItem)
    }
    @objc private func previousPersona() { onStep?(-1) }
    @objc private func nextPersona() { onStep?(1) }
    @objc private func hidePersona() { onHide?() }
    @objc private func choosePersona() { if let id = picker.selectedItem?.representedObject as? UUID { onSelect?(id) } }
    @objc private func toggleLock() { onLock?(!locked) }
    @objc private func changeSize(_ sender: NSMenuItem) { if let delta = sender.representedObject as? Double { onSizeChange?(delta) } }
    @objc private func choosePosition(_ sender: NSMenuItem) {
        guard let name = sender.representedObject as? String, let anchor = FloatingControlAnchor(rawValue: name) else { return }
        hideGuides(); dragHandle.cancel(); placement.position.anchor = anchor; position(near: nil); save(); rebuildOptions()
    }
    private static func screenID(_ screen: NSScreen) -> UInt32? {
        (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
    }
    private func screen(near rect: CGRect?) -> NSScreen? {
        if let rect, let best = NSScreen.screens.max(by: { overlap(rect, $0.visibleFrame) < overlap(rect, $1.visibleFrame) }), overlap(rect, best.visibleFrame) > 0 { return best }
        return NSScreen.screens.first { Self.screenID($0) == placement.screenID && placement.screenID != nil }
            ?? NSScreen.main ?? NSScreen.screens.first
    }
    private func overlap(_ lhs: CGRect, _ rhs: CGRect) -> CGFloat {
        let intersection = lhs.intersection(rhs); return intersection.isNull ? 0 : intersection.width * intersection.height
    }
    private func position(near rect: CGRect?) {
        guard let window, let screen = screen(near: placement.screenID == nil ? rect : nil) else { return }
        placement.screenID = Self.screenID(screen)
        window.setFrame(placement.position.frame(size: window.frame.size, in: screen.visibleFrame), display: true)
    }
    private func previewDrag() {
        guard let window, let screen = screen(near: window.frame) else { return }
        let active = FloatingControlGeometry.nearestAnchor(to: window.frame, in: screen.visibleFrame)
        MainActor.assumeIsolated {
            if guides == nil { guides = FloatingControlGuideController() }
            guides?.show(controlFrame: window.frame, visibleFrame: screen.visibleFrame, activeAnchor: active, below: window)
        }
    }
    private func finishDrag() {
        defer { hideGuides() }
        guard let window, let screen = screen(near: window.frame) else { return }
        let anchor = FloatingControlGeometry.nearestAnchor(to: window.frame, in: screen.visibleFrame)
        let frame = anchor.map { FloatingControlGeometry.frame(anchor: $0, size: window.frame.size, visibleFrame: screen.visibleFrame) }
            ?? FloatingControlGeometry.clamp(window.frame, to: screen.visibleFrame)
        placement.position.move(to: frame, in: screen.visibleFrame, anchor: anchor)
        placement.screenID = Self.screenID(screen); window.setFrame(frame, display: true); save(); rebuildOptions()
    }
    private func hideGuides() { MainActor.assumeIsolated { guides?.hide() } }
    private func save() {
        guard !storageBlocked else { return }
        do { savedData = try PersonaStorage.write(placement.validated(), to: url, expected: savedData) }
        catch { storageBlocked = true; notice = "Persona controls could not save their position. The previous file is preserved." }
    }
}

private final class PersonaHUDDragHandle: NSView {
    var onDrag: (() -> Void)?
    var onEnd: (() -> Void)?
    private var start: CGPoint?
    private var origin: CGPoint?
    private var dragging = false
    override init(frame: NSRect) {
        super.init(frame: frame)
        setAccessibilityElement(true); setAccessibilityRole(.image)
        setAccessibilityLabel("Drag persona controls; named positions are available in options")
        toolTip = "Drag to move controls. Use Control position for named locations."
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func draw(_ dirtyRect: NSRect) {
        NSImage(systemSymbolName: "line.3.horizontal", accessibilityDescription: nil)?
            .draw(in: bounds.insetBy(dx: 4, dy: 10))
    }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseDown(with event: NSEvent) {
        guard let window else { return }; start = window.convertPoint(toScreen: event.locationInWindow); origin = window.frame.origin
    }
    override func mouseDragged(with event: NSEvent) {
        guard let window, let start, let origin else { return }
        let point = window.convertPoint(toScreen: event.locationInWindow)
        guard dragging || hypot(point.x - start.x, point.y - start.y) >= 4 else { return }
        dragging = true; window.setFrameOrigin(CGPoint(x: origin.x + point.x - start.x, y: origin.y + point.y - start.y)); onDrag?()
    }
    override func mouseUp(with event: NSEvent) { if dragging { onEnd?() }; cancel() }
    func cancel() { start = nil; origin = nil; dragging = false }
    override func resetCursorRects() { addCursorRect(bounds, cursor: .openHand) }
}
