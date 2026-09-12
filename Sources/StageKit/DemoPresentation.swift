import AppKit
import SwiftUI
import AVFoundation

final class DemoPresentation: NSObject, NSWindowDelegate {
    var onEnd: (() -> Void)?
    private var window: DemoStageWindow?
    private let capture: DemoCapture
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
        window.contentView = NSHostingView(rootView: DemoStageContent(scene: scene, backdrop: backdrop, logo: logo, hand: hand, capture: capture) { [weak self] in self?.end() })
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
    override func cancelOperation(_ sender: Any?) { onEscape?() }
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
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

private struct DemoStageContent: View {
    let scene: DemoScene
    let backdrop: NSImage
    let logo: NSImage?
    let hand: NSImage?
    @ObservedObject var capture: DemoCapture
    let end: () -> Void
    @State private var controlsVisible = true
    @State private var fitToSource = true
    @State private var hideControls: DispatchWorkItem?
    @State private var choosingSource = false
    @State private var hoveringControls = false
    private var liveScene: DemoScene {
        var value = scene
        if fitToSource, capture.dimensions.height > 0 {
            var viewport = scene.viewport ?? .legacy
            viewport.aspect = capture.dimensions.width / capture.dimensions.height
            value.viewport = (try? viewport.validated()) ?? viewport
        }
        return value
    }
    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .topTrailing) {
                DemoStageSurface(scene: liveScene, image: backdrop, logo: logo, hand: hand, previewLayer: capture.previewLayer, live: capture.live)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                if scene.showsPhone && !capture.live {
                    let viewport = ViewportGeometry(scene: liveScene, size: geometry.size).screen
                    VStack(spacing: 14) {
                        Image(systemName: "cable.connector").font(.largeTitle)
                        Text(capture.message).font(.body).multilineTextAlignment(.center)
                        Button("Choose source…") { choosingSource = true; showControls() }
                        Button("Reconnect") { capture.reconnect() }
                    }.padding(20).frame(width: max(120, viewport.width - 20))
                        .foregroundStyle(.white)
                        .position(x: viewport.midX, y: geometry.size.height - viewport.midY)
                }
                if controlsVisible || choosingSource {
                    HStack(spacing: 14) {
                        if scene.showsPhone {
                            Button("Source…") { choosingSource = true }
                            Button("Reconnect") { capture.reconnect(); showControls() }.help("Reconnect device · ⌘R")
                            Toggle("Match device proportions", isOn: $fitToSource).toggleStyle(.checkbox)
                        }
                        Button("End demo · Esc", action: end).keyboardShortcut(.cancelAction)
                    }.padding(12).background(.ultraThickMaterial, in: RoundedRectangle(cornerRadius: 12)).padding(18)
                        .onHover { hoveringControls = $0; showControls() }
                }
            }.background(.black)
                .onContinuousHover { phase in if case .active = phase { showControls() } }
                .onAppear { showControls() }
                .onDisappear { hideControls?.cancel() }
                .sheet(isPresented: $choosingSource) {
                    VStack(alignment: .leading, spacing: 18) {
                        HStack { Text("Device screen").font(.title2.bold()); Spacer(); Button("Done") { choosingSource = false; showControls() } }
                        Text("Connect an unlocked iPhone or iPad by USB and trust this Mac. External video sources also work; Android needs a compatible video feed.").foregroundStyle(.secondary)
                        NativePresentationApps { capture.reportNotice($0) }
                        if capture.sources.isEmpty { Text("No external sources found.") }
                        ForEach(capture.sources) { source in
                            Button {
                                capture.select(source.id); choosingSource = false; showControls()
                            } label: {
                                HStack { Image(systemName: source.isScreen ? "iphone" : "video"); Text(source.name); Spacer(); if capture.selectedID == source.id { Image(systemName: "checkmark") } }
                            }.buttonStyle(.bordered)
                        }
                        Text(capture.message).font(.caption).foregroundStyle(.secondary)
                        Button("Refresh devices") { capture.refresh() }
                    }.padding(24).frame(width: 460)
                }
        }.ignoresSafeArea()
    }
    private func showControls() {
        controlsVisible = true; hideControls?.cancel()
        guard !hoveringControls, !choosingSource else { return }
        let work = DispatchWorkItem { controlsVisible = false }
        hideControls = work; DispatchQueue.main.asyncAfter(deadline: .now() + 3, execute: work)
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
