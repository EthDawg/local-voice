import AppKit
import SwiftUI
import AVFoundation

final class DemoPresentation: NSObject, NSWindowDelegate {
    var onEnd: (() -> Void)?
    private var window: DemoStageWindow?
    private let capture: DemoCapture
    private let controls: PresentationControlsModel
    private let scene: DemoScene
    private let backdrop: NSImage
    private let logo: NSImage?
    private let hand: NSImage?
    private let persona: NSImage?
    private let screen: NSScreen?
    private var ending = false
    private var entering = false
    private var keepAwake: NSObjectProtocol?
    init(scene: DemoScene, image: NSImage, logo: NSImage?, hand: NSImage?, persona: NSImage? = nil, screen: NSScreen?, root: URL) {
        self.scene = scene; backdrop = image; self.logo = logo; self.hand = hand; self.persona = persona; self.screen = screen
        capture = DemoCapture(root: root)
        controls = PresentationControlsModel(root: root)
        super.init()
    }
    func start() {
        keepAwake = ProcessInfo.processInfo.beginActivity(options: [.userInitiated, .idleDisplaySleepDisabled], reason: "Presenting a Workbench demo")
        let frame = screen?.visibleFrame ?? CGRect(x: 80, y: 80, width: 1100, height: 720)
        let window = DemoStageWindow(contentRect: frame, styleMask: [.titled, .closable, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
        window.title = scene.name + " · Demo"
        window.titleVisibility = .hidden; window.titlebarAppearsTransparent = true
        window.collectionBehavior = [.fullScreenPrimary]
        window.tabbingMode = .disallowed
        window.isReleasedWhenClosed = false; window.delegate = self
        window.onEscape = { [weak self] in
            guard let self else { return }
            if !self.controls.handleEscape() { self.end() }
        }
        window.onReconnect = { [weak self] in self?.capture.reconnect() }
        window.onRevealControls = { [weak self] in self?.controls.revealForKeyboard() }
        window.contentView = NSHostingView(rootView: DemoStageContent(scene: scene, backdrop: backdrop, logo: logo, hand: hand, persona: persona, capture: capture, controls: controls) { [weak self] in self?.end() })
        self.window = window
        NSApp.activate(ignoringOtherApps: true); window.makeKeyAndOrderFront(nil)
        entering = true; window.toggleFullScreen(nil)
        if scene.showsPhone { capture.start() }
    }
    func bringForward() { NSApp.activate(ignoringOtherApps: true); window?.makeKeyAndOrderFront(nil) }
    func end() {
        guard !ending else { return }; ending = true; capture.stop(); releaseKeepAwake()
        if entering { return }
        if window?.styleMask.contains(.fullScreen) == true { window?.toggleFullScreen(nil) }
        else { finish() }
    }
    private func finish() {
        controls.stop()
        capture.stop(); releaseKeepAwake()
        window?.delegate = nil; window?.orderOut(nil); window?.contentView = nil; window?.close(); window = nil
        let callback = onEnd; onEnd = nil; callback?()
    }
    private func releaseKeepAwake() {
        if let keepAwake { ProcessInfo.processInfo.endActivity(keepAwake); self.keepAwake = nil }
    }
    deinit { if let keepAwake { ProcessInfo.processInfo.endActivity(keepAwake) } }
    func windowDidEnterFullScreen(_ notification: Notification) {
        entering = false
        if ending { window?.toggleFullScreen(nil) }
    }
    func windowDidExitFullScreen(_ notification: Notification) { entering = false; ending = true; finish() }
    func windowDidFailToEnterFullScreen(_ window: NSWindow) { entering = false; if ending { finish() } }
    func windowDidFailToExitFullScreen(_ window: NSWindow) { finish() }
    func windowShouldClose(_ sender: NSWindow) -> Bool { end(); return false }
}

private final class DemoStageWindow: NSWindow {
    var onEscape: (() -> Void)?
    var onReconnect: (() -> Void)?
    var onRevealControls: (() -> Void)?
    override func cancelOperation(_ sender: Any?) {
        if let attachedSheet { attachedSheet.cancelOperation(sender) } else { onEscape?() }
    }
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard attachedSheet == nil else { return super.performKeyEquivalent(with: event) }
        if PresentationControlsPolicy.isRevealCommand(characters: event.charactersIgnoringModifiers,
            command: event.modifierFlags.contains(.command), option: event.modifierFlags.contains(.option),
            control: event.modifierFlags.contains(.control)) {
            onRevealControls?(); return true
        }
        if event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command,
           event.charactersIgnoringModifiers?.lowercased() == "r" {
            onReconnect?(); return true
        }
        return super.performKeyEquivalent(with: event)
    }
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { onEscape?() } else { super.keyDown(with: event) }
    }
}

/// AppKit owns Command-/ and Escape; the model owns only this presentation's
/// controls and placement. Capture and scene state never depend on expansion.
private final class PresentationControlsModel: ObservableObject {
    @Published private(set) var policy = PresentationControlsPolicy()
    @Published private(set) var focusRequest = 0
    @Published private(set) var placement = PresentationControlPlacement()
    @Published private(set) var dragFrame: CGRect?
    @Published private(set) var snapAnchor: FloatingControlAnchor?
    @Published private(set) var placementNotice: String?
    private let url: URL
    private var archiveData: Data?
    private var storageBlocked = false
    private var dragStart: CGRect?
    private var suppressClickUntil: TimeInterval = 0
    var controlSize: CGSize { policy.isExpanded ? CGSize(width: 304, height: 192) : CGSize(width: 76, height: 40) }

    init(root: URL) {
        url = root.appendingPathComponent("presentation-controls.json")
        do {
            archiveData = try PersonaStorage.read(url)
            if let archiveData { placement = try JSONDecoder().decode(PresentationControlPlacement.self, from: archiveData).validated() }
        } catch {
            storageBlocked = true
            placementNotice = "The previous control position could not be read. Its file is unchanged; new positions apply to this presentation only."
        }
    }
    func start() { policy.close() }
    func stop() { dragStart = nil; dragFrame = nil; snapAnchor = nil }
    func close() { stop(); policy.close(); focusRequest += 1 }
    func toggleFromTile() {
        guard ProcessInfo.processInfo.systemUptime >= suppressClickUntil, dragFrame == nil else { return }
        policy.toggle()
    }
    func revealForKeyboard() { stop(); policy.open(); focusRequest += 1 }
    func handleEscape() -> Bool {
        if policy.handleEscape() { stop(); focusRequest += 1; return true }
        return false
    }
    func frame(in size: CGSize) -> CGRect {
        let visible = CGRect(origin: .zero, size: size)
        return dragFrame.map { FloatingControlGeometry.clamp($0, to: visible) }
            ?? placement.frame(size: controlSize, in: visible)
    }
    func setAnchor(_ anchor: FloatingControlAnchor) {
        stop(); placement.anchor = anchor; save()
    }
    func drag(translation: CGSize, in size: CGSize) {
        let visible = CGRect(origin: .zero, size: size)
        if dragStart == nil { dragStart = frame(in: size) }
        guard let start = dragStart else { return }
        let proposed = start.offsetBy(dx: translation.width, dy: -translation.height)
        let bounded = FloatingControlGeometry.clamp(proposed, to: visible)
        dragFrame = bounded
        snapAnchor = FloatingControlGeometry.nearestAnchor(to: bounded, in: visible)
    }
    func finishDrag(in size: CGSize) {
        guard let dragFrame else { return }
        let visible = CGRect(origin: .zero, size: size)
        let frame = snapAnchor.map { FloatingControlGeometry.frame(anchor: $0, size: controlSize, visibleFrame: visible) } ?? dragFrame
        placement.move(to: frame, in: visible, anchor: snapAnchor)
        suppressClickUntil = ProcessInfo.processInfo.systemUptime + 0.25
        stop(); save()
    }
    private func save() {
        guard !storageBlocked else { return }
        do { archiveData = try PersonaStorage.write(try placement.validated(), to: url, expected: archiveData) }
        catch {
            storageBlocked = true
            placementNotice = "The control position could not be saved. Its previous file is unchanged."
        }
    }
}

private struct DemoStageContent: View {
    private enum Control: Hashable { case tile, source, reconnect, position, close, end, deviceSource, deviceReconnect }
    let scene: DemoScene
    let backdrop: NSImage
    let logo: NSImage?
    let hand: NSImage?
    let persona: NSImage?
    @ObservedObject var capture: DemoCapture
    @ObservedObject var controls: PresentationControlsModel
    let end: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @State private var fitToSource = true
    @State private var choosingSource = false
    @FocusState private var focusedControl: Control?
    private var liveScene: DemoScene {
        var value = scene
        if fitToSource, capture.dimensions.height > 0 {
            var viewport = scene.viewport ?? .legacy
            viewport.aspect = capture.dimensions.width / capture.dimensions.height
            value.viewport = (try? viewport.validated()) ?? viewport
        }
        return value
    }
    private var sourceName: String {
        guard scene.showsPhone else { return "Saved scene" }
        return capture.sources.first(where: { $0.id == capture.selectedID })?.name
            ?? (capture.selectedID == nil ? "Choose a source" : "Selected device")
    }
    private var inwardChevron: String {
        switch controls.placement.anchor {
        case .top, .topLeft, .topRight: return "chevron.down"
        case .bottom, .bottomLeft, .bottomRight: return "chevron.up"
        case .left: return "chevron.right"
        case .right: return "chevron.left"
        case nil: return controls.placement.x > 0.5 ? "chevron.left" : "chevron.right"
        }
    }
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                DemoStageSurface(scene: liveScene, image: backdrop, logo: logo, hand: hand, persona: persona, previewLayer: capture.previewLayer, live: capture.live)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .onTapGesture { if controls.policy.isExpanded { controls.close() } }
                if scene.showsPhone && !capture.live {
                    let viewport = ViewportGeometry(scene: liveScene, size: geometry.size).screen
                    VStack(spacing: 14) {
                        Image(systemName: "cable.connector").font(.largeTitle)
                        Text(capture.message).font(.body).multilineTextAlignment(.center)
                        Button("Choose source…", action: openSource).focused($focusedControl, equals: .deviceSource)
                        Button("Reconnect") { capture.reconnect() }.focused($focusedControl, equals: .deviceReconnect)
                    }.padding(20).frame(width: max(120, viewport.width - 20))
                        .foregroundStyle(.white)
                        .position(x: viewport.midX, y: geometry.size.height - viewport.midY)
                }
                if controls.dragFrame != nil, let anchor = controls.snapAnchor {
                    let destination = FloatingControlGeometry.frame(anchor: anchor, size: controls.controlSize,
                                                                     visibleFrame: CGRect(origin: .zero, size: geometry.size))
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.accentColor.opacity(0.16))
                        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 2, dash: [5, 4])))
                        .frame(width: destination.width, height: destination.height)
                        .position(x: destination.midX, y: geometry.size.height - destination.midY)
                        .allowsHitTesting(false).accessibilityHidden(true)
                }
                let frame = controls.frame(in: geometry.size)
                Group {
                    if controls.policy.isExpanded { expandedControls(in: geometry.size) }
                    else { tile(in: geometry.size) }
                }
                .frame(width: frame.width, height: frame.height)
                .background {
                    if reduceTransparency {
                        RoundedRectangle(cornerRadius: 12).fill(Color(nsColor: .windowBackgroundColor))
                    } else {
                        RoundedRectangle(cornerRadius: 12).fill(.thickMaterial)
                    }
                }
                .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.primary.opacity(0.16)))
                .position(x: frame.midX, y: geometry.size.height - frame.midY)
                .animation(reduceMotion || controls.dragFrame != nil ? nil : .easeOut(duration: 0.16), value: controls.policy.isExpanded)
            }.background(.black).coordinateSpace(name: "presentation-controls")
                .onAppear { controls.start() }
                .onDisappear { controls.stop() }
                .onChange(of: controls.focusRequest) { _, _ in
                    focusedControl = controls.policy.isExpanded ? (scene.showsPhone ? .source : .close) : .tile
                }
                .sheet(isPresented: $choosingSource) { sourceSheet }
        }.ignoresSafeArea()
    }
    private func dragGesture(in size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 5, coordinateSpace: .named("presentation-controls"))
            .onChanged { controls.drag(translation: $0.translation, in: size) }
            .onEnded { _ in controls.finishDrag(in: size) }
    }
    private func tile(in size: CGSize) -> some View {
        Button { controls.toggleFromTile() } label: {
            HStack(spacing: 0) {
                Image(systemName: "iphone").font(.system(size: 17, weight: .medium))
                    .frame(width: 42, height: 40)
                Divider().frame(height: 18)
                Image(systemName: inwardChevron).font(.system(size: 11, weight: .semibold))
                    .frame(width: 33, height: 40)
            }.contentShape(Rectangle())
        }.buttonStyle(.plain).focused($focusedControl, equals: .tile)
            .simultaneousGesture(dragGesture(in: size))
            .accessibilityLabel("Open presentation controls")
            .accessibilityHint("Command Slash also opens controls. Use the Position menu to move them.")
            .help("Click or ⌘/ for controls. Drag to move. Visible when sharing this screen.")
    }
    private func expandedControls(in size: CGSize) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: "iphone")
                    Text(sourceName).font(.callout.weight(.semibold)).lineLimit(1)
                    Spacer(minLength: 0)
                }.contentShape(Rectangle()).gesture(dragGesture(in: size))
                    .help("Drag to move, or choose Position")
                Button { controls.close() } label: { Image(systemName: "xmark") }
                    .buttonStyle(.plain).frame(width: 24, height: 24).focused($focusedControl, equals: .close)
                    .accessibilityLabel("Close presentation controls").help("Close controls · Esc")
            }
            Text(scene.showsPhone ? (capture.live ? "Use your phone for taps, typing and Dictation." : capture.message) : "Showing your saved scene.")
                .font(.caption).foregroundStyle(.secondary).lineLimit(2).frame(height: 30, alignment: .topLeading)
            HStack {
                if scene.showsPhone {
                    Button("Source…", action: openSource).focused($focusedControl, equals: .source)
                    Button("Reconnect") { capture.reconnect() }
                        .focused($focusedControl, equals: .reconnect).help("Reconnect device · ⌘R")
                }
                Spacer()
            }.frame(height: 28)
            Divider()
            HStack {
                Menu("Position") {
                    ForEach(FloatingControlAnchor.allCases) { anchor in
                        Button { controls.setAnchor(anchor) } label: {
                            if controls.placement.anchor == anchor { Label(anchor.title, systemImage: "checkmark") }
                            else { Text(anchor.title) }
                        }
                    }
                }.fixedSize().focused($focusedControl, equals: .position)
                if let notice = controls.placementNotice {
                    Image(systemName: "exclamationmark.circle").foregroundStyle(.secondary).help(notice).accessibilityLabel(notice)
                }
                Spacer()
                Button("End", action: end).focused($focusedControl, equals: .end)
                    .accessibilityLabel("End presentation").help("End presentation. Escape ends it when controls are closed.")
            }.frame(height: 28)
        }.padding(12)
            .accessibilityElement(children: .contain).accessibilityLabel("Presentation controls")
    }
    private func openSource() {
        controls.close()
        choosingSource = true
    }
    private var sourceSheet: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text("Device screen").font(.title2.bold())
                Spacer()
                Button("Done") { choosingSource = false }.keyboardShortcut(.defaultAction)
            }
            Text("Connect an unlocked iPhone or iPad by USB and trust this Mac. External video sources also work; Android needs a compatible video feed.").foregroundStyle(.secondary)
            if capture.sources.isEmpty { Text("No external sources found.") }
            ForEach(capture.sources) { source in
                Button {
                    capture.select(source.id); choosingSource = false
                } label: {
                    HStack { Image(systemName: source.isScreen ? "iphone" : "video"); Text(source.name); Spacer(); if capture.selectedID == source.id { Image(systemName: "checkmark") } }
                }.buttonStyle(.bordered)
            }
            Text(capture.message).font(.caption).foregroundStyle(.secondary)
            Toggle("Match device proportions", isOn: $fitToSource).toggleStyle(.checkbox)
            if capture.dimensions.width > 0 && capture.dimensions.height > 0 {
                Text("Video size: \(Int(capture.dimensions.width)) × \(Int(capture.dimensions.height))")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Button("Refresh devices") { capture.refresh() }
            Divider()
            NativePresentationApps { capture.reportNotice($0) }
        }.padding(24).frame(width: 460).onExitCommand { choosingSource = false }
    }
}

private struct DemoStageSurface: NSViewRepresentable {
    let scene: DemoScene
    let image: NSImage
    let logo: NSImage?
    let hand: NSImage?
    let persona: NSImage?
    let previewLayer: AVCaptureVideoPreviewLayer
    let live: Bool
    func makeNSView(context: Context) -> DemoStageSurfaceView { DemoStageSurfaceView(previewLayer: previewLayer) }
    func updateNSView(_ view: DemoStageSurfaceView, context: Context) {
        let changed = view.scene != scene || view.backdrop !== image || view.logo !== logo || view.hand !== hand || view.persona !== persona
        view.scene = scene; view.backdrop = image; view.logo = logo; view.hand = hand; view.persona = persona; view.isLive = live
        if changed { view.needsDisplay = true; view.needsLayout = true; view.refreshLogo() }
    }
}

/// Clip the actual feed with precisely the same inner radius used by the border.
final class DemoStageSurfaceView: NSView {
    var scene: DemoScene?
    var backdrop: NSImage?
    var logo: NSImage?
    var hand: NSImage?
    var persona: NSImage?
    private let videoLayer: AVCaptureVideoPreviewLayer
    private let branding = DemoStageLogoView()
    var isLive = false { didSet { videoLayer.isHidden = !isLive || scene?.showsPhone != true } }
    init(previewLayer: AVCaptureVideoPreviewLayer) {
        videoLayer = previewLayer
        super.init(frame: .zero); wantsLayer = true
        videoLayer.videoGravity = .resizeAspect; videoLayer.masksToBounds = true
        videoLayer.backgroundColor = NSColor.black.cgColor
        layer?.addSublayer(videoLayer)
        // Branding is the top scene layer in exports and live presentations.
        branding.wantsLayer = true; addSubview(branding)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func layout() {
        super.layout()
        guard let scene else { return }
        branding.frame = bounds; branding.needsDisplay = true
        let geometry = ViewportGeometry(scene: scene, size: bounds.size)
        CATransaction.begin(); CATransaction.setDisableActions(true)
        videoLayer.frame = geometry.screen; videoLayer.cornerRadius = geometry.innerRadius
        videoLayer.isHidden = !scene.showsPhone || !isLive
        CATransaction.commit()
    }
    override func draw(_ dirtyRect: NSRect) {
        guard let scene, let backdrop else { return }
        SceneRenderer.draw(scene, image: backdrop, size: bounds.size, handImage: hand)
    }
    func refreshLogo() { branding.scene = scene; branding.image = logo; branding.persona = persona; branding.needsDisplay = true }
}

private final class DemoStageLogoView: NSView {
    var scene: DemoScene?
    var image: NSImage?
    var persona: NSImage?
    override var isOpaque: Bool { false }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override func draw(_ dirtyRect: NSRect) {
        guard let scene else { return }
        SceneRenderer.drawLogo(scene, size: bounds.size, image: image)
        SceneRenderer.drawPersona(scene, size: bounds.size, image: persona)
    }
}
