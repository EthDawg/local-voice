import AppKit
import SwiftUI
import AVFoundation

final class DemoPresentation: NSObject, NSWindowDelegate {
    var onEnd: (() -> Void)?
    private var window: DemoStageWindow?
    private let capture: DemoCapture
    private let controls = PresentationControlsModel()
    private let scene: DemoScene
    private let backdrop: NSImage
    private let logo: NSImage?
    private let hand: NSImage?
    private let screen: NSScreen?
    private var ending = false
    private var entering = false
    private var keepAwake: NSObjectProtocol?
    init(scene: DemoScene, image: NSImage, logo: NSImage?, hand: NSImage?, screen: NSScreen?, root: URL) {
        self.scene = scene; backdrop = image; self.logo = logo; self.hand = hand; self.screen = screen
        capture = DemoCapture(root: root)
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
        window.onEscape = { [weak self] in self?.end() }
        window.onReconnect = { [weak self] in self?.capture.reconnect() }
        window.onRevealControls = { [weak self] in self?.controls.revealForKeyboard() }
        window.contentView = NSHostingView(rootView: DemoStageContent(scene: scene, backdrop: backdrop, logo: logo, hand: hand, capture: capture, controls: controls) { [weak self] in self?.end() })
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
    override func cancelOperation(_ sender: Any?) { onEscape?() }
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
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

/// AppKit owns the reveal command so it remains available while the toolbar
/// is absent from the SwiftUI hierarchy. All state updates are on the main queue.
private final class PresentationControlsModel: ObservableObject {
    @Published private(set) var policy = PresentationControlsPolicy()
    @Published private(set) var focusRequest = 0
    private var hideWork: DispatchWorkItem?
    private var voiceOverObservation: NSKeyValueObservation?
    private var now: TimeInterval { ProcessInfo.processInfo.systemUptime }

    func start() {
        setHold(.voiceOver, active: NSWorkspace.shared.isVoiceOverEnabled)
        voiceOverObservation = NSWorkspace.shared.observe(\.isVoiceOverEnabled, options: [.new]) { [weak self] workspace, _ in
            let enabled = workspace.isVoiceOverEnabled
            DispatchQueue.main.async { self?.setHold(.voiceOver, active: enabled) }
        }
        reveal()
    }
    func stop() { hideWork?.cancel(); hideWork = nil; voiceOverObservation = nil }
    func reveal() { policy.reveal(at: now); scheduleHide() }
    func revealForKeyboard() { reveal(); focusRequest += 1 }
    func setHold(_ hold: PresentationControlsPolicy.Hold, active: Bool) {
        guard policy.holds.contains(hold) != active else { return }
        policy.setHold(hold, active: active, at: now); scheduleHide()
    }
    func pointerMoved(y: CGFloat?) {
        var next = policy
        next.pointerMoved(y: y.map(Double.init), at: now)
        guard next != policy else { return }
        policy = next; scheduleHide()
    }
    private func scheduleHide() {
        hideWork?.cancel(); hideWork = nil
        guard let deadline = policy.hideDeadline else { return }
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.policy.hideIfDue(at: self.now)
        }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + max(0, deadline - now), execute: work)
    }
    deinit { hideWork?.cancel() }
}

private struct DemoStageContent: View {
    private enum Control: Hashable { case source, reconnect, pin, end, deviceSource, deviceReconnect }
    let scene: DemoScene
    let backdrop: NSImage
    let logo: NSImage?
    let hand: NSImage?
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
    private var sourceStatus: String {
        guard scene.showsPhone else { return "Scene only" }
        if capture.live { return "Live" }
        if capture.selectedID == nil { return "No device" }
        if !capture.sources.contains(where: { $0.id == capture.selectedID }) { return "Waiting for device" }
        // Permission, negotiation and reconnect states have more precise detail
        // in capture.message. Do not label an unverified feed as live.
        return "Not live"
    }
    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .topTrailing) {
                DemoStageSurface(scene: liveScene, image: backdrop, logo: logo, hand: hand, previewLayer: capture.previewLayer, live: capture.live)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .onTapGesture { focusedControl = nil }
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
                if controls.policy.isVisible {
                    toolbar.frame(maxWidth: 620).padding(18).transition(.opacity)
                }
            }.background(.black)
                .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: controls.policy.isVisible)
                .onContinuousHover { phase in
                    switch phase {
                    case .active(let location): controls.pointerMoved(y: location.y)
                    case .ended: controls.pointerMoved(y: nil)
                    }
                }
                .onAppear { controls.start() }
                .onDisappear { controls.stop() }
                .onChange(of: focusedControl) { _, value in controls.setHold(.keyboardFocus, active: value != nil) }
                .onChange(of: controls.focusRequest) { _, _ in focusedControl = scene.showsPhone ? .source : .pin }
                .onChange(of: choosingSource) { _, value in controls.setHold(.sheet, active: value) }
                .sheet(isPresented: $choosingSource) { sourceSheet }
        }.ignoresSafeArea()
    }
    private var toolbar: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 3) {
                    Label(sourceStatus, systemImage: capture.live && scene.showsPhone ? "circle.fill" : "circle")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(capture.live && scene.showsPhone ? Color.green : Color.secondary)
                    Text(sourceName).font(.callout.weight(.medium)).lineLimit(1).frame(maxWidth: 190, alignment: .leading)
                }.help(scene.showsPhone ? capture.message : "Showing your saved scene without a device feed")
                    .accessibilityElement(children: .combine)
                if scene.showsPhone {
                    Button("Source…", action: openSource).focused($focusedControl, equals: .source)
                    Button("Reconnect") { capture.reconnect(); controls.reveal() }
                        .focused($focusedControl, equals: .reconnect).help("Reconnect device · ⌘R")
                }
                Button("End demo · Esc", action: end).keyboardShortcut(.cancelAction)
                    .focused($focusedControl, equals: .end)
                    .accessibilityLabel("End demo").accessibilityHint("Escape also ends the demo")
            }
            HStack(spacing: 16) {
                Toggle("Keep controls visible", isOn: Binding(
                    get: { controls.policy.holds.contains(.pinned) },
                    set: { controls.setHold(.pinned, active: $0) }))
                    .toggleStyle(.checkbox).focused($focusedControl, equals: .pin)
                    .help("Keep these controls visible for this demo")
                Spacer(minLength: 0)
                Text("Top edge or ⌘/ to show").foregroundStyle(.secondary)
                    .accessibilityLabel("Move to the top edge or press Command Slash to show controls")
            }.font(.caption)
        }.padding(12)
            .background {
                if reduceTransparency {
                    RoundedRectangle(cornerRadius: 12).fill(Color(nsColor: .windowBackgroundColor))
                } else {
                    RoundedRectangle(cornerRadius: 12).fill(.thickMaterial)
                }
            }
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.primary.opacity(0.12)))
            .onHover { controls.setHold(.toolbarHover, active: $0) }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Presentation controls")
            .help("These controls can appear in your screen share")
    }
    private func openSource() {
        controls.setHold(.sheet, active: true)
        choosingSource = true
    }
    private var sourceSheet: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text("Device screen").font(.title2.bold())
                Spacer()
                Button("Done") { choosingSource = false; controls.reveal() }.keyboardShortcut(.defaultAction)
            }
            Text("Connect an unlocked iPhone or iPad by USB and trust this Mac. External video sources also work; Android needs a compatible video feed.").foregroundStyle(.secondary)
            if capture.sources.isEmpty { Text("No external sources found.") }
            ForEach(capture.sources) { source in
                Button {
                    capture.select(source.id); choosingSource = false; controls.reveal()
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
        }.padding(24).frame(width: 460)
    }
}

private struct DemoStageSurface: NSViewRepresentable {
    let scene: DemoScene
    let image: NSImage
    let logo: NSImage?
    let hand: NSImage?
    let previewLayer: AVCaptureVideoPreviewLayer
    let live: Bool
    func makeNSView(context: Context) -> DemoStageSurfaceView { DemoStageSurfaceView(previewLayer: previewLayer) }
    func updateNSView(_ view: DemoStageSurfaceView, context: Context) {
        let changed = view.scene != scene || view.backdrop !== image || view.logo !== logo || view.hand !== hand
        view.scene = scene; view.backdrop = image; view.logo = logo; view.hand = hand; view.isLive = live
        if changed { view.needsDisplay = true; view.needsLayout = true; view.refreshLogo() }
    }
}

/// Clip the actual feed with precisely the same inner radius used by the border.
final class DemoStageSurfaceView: NSView {
    var scene: DemoScene?
    var backdrop: NSImage?
    var logo: NSImage?
    var hand: NSImage?
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
    func refreshLogo() { branding.scene = scene; branding.image = logo; branding.needsDisplay = true }
}

private final class DemoStageLogoView: NSView {
    var scene: DemoScene?
    var image: NSImage?
    override var isOpaque: Bool { false }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override func draw(_ dirtyRect: NSRect) {
        guard let scene else { return }
        SceneRenderer.drawLogo(scene, size: bounds.size, image: image)
    }
}
