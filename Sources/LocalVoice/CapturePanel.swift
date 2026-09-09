import AppKit
import SwiftUI

/// A non-activating panel keeps the destination app focused when Finish is clicked.
final class CapturePanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

final class CaptureHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

enum CapturePanelPlacement {
    static let size = NSSize(width: 460, height: 88)
    static func origin(saved: NSPoint?, screens: [NSRect], preferred: NSRect) -> NSPoint {
        let proposed = saved ?? NSPoint(x: preferred.maxX - size.width - 24, y: preferred.maxY - size.height - 32)
        let frame = screens.first { $0.contains(proposed) } ?? preferred
        return NSPoint(x: min(max(proposed.x, frame.minX + 8), frame.maxX - size.width - 8),
                       y: min(max(proposed.y, frame.minY + 8), frame.maxY - size.height - 8))
    }
}

@MainActor
final class CapturePanelController: NSWindowController, NSWindowDelegate {
    private let positionKey = "capturePanelOrigin.v1"
    private var positioning = false
    init(model: AppModel) {
        let panel = CapturePanel(contentRect: NSRect(origin: .zero, size: CapturePanelPlacement.size),
                                 styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        super.init(window: panel)
        panel.title = "Workbench Voice dictation"
        panel.isFloatingPanel = true; panel.level = .floating; panel.hidesOnDeactivate = false
        panel.isMovable = true
        panel.isOpaque = false; panel.backgroundColor = .clear; panel.hasShadow = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.contentView = CaptureHostingView(rootView: RecordingOverlay(model: model))
        panel.setContentSize(CapturePanelPlacement.size)
        panel.delegate = self
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    func update(model: AppModel) {
        guard let window else { return }
        if model.previewingPanel || [.recording, .transcribing, .cleaning].contains(model.phase) {
            if !window.isVisible { position() }
            window.orderFrontRegardless()
        } else { window.orderOut(nil) }
    }
    func position(reset: Bool = false) {
        guard let window, let screen = NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) }) ?? NSScreen.main else { return }
        if reset { UserDefaults.standard.removeObject(forKey: positionKey) }
        let saved = UserDefaults.standard.string(forKey: positionKey).map(NSPointFromString)
        positioning = true
        window.setFrameOrigin(CapturePanelPlacement.origin(saved: saved, screens: NSScreen.screens.map(\.visibleFrame), preferred: screen.visibleFrame))
        positioning = false
    }
    func windowDidMove(_ notification: Notification) {
        guard !positioning, let window, window.isVisible else { return }
        UserDefaults.standard.set(NSStringFromPoint(window.frame.origin), forKey: positionKey)
    }
    func finishDragging() {
        guard let window, let preferred = window.screen?.visibleFrame ?? NSScreen.main?.visibleFrame else { return }
        let origin = CapturePanelPlacement.origin(saved: window.frame.origin, screens: NSScreen.screens.map(\.visibleFrame), preferred: preferred)
        window.setFrameOrigin(origin)
        UserDefaults.standard.set(NSStringFromPoint(origin), forKey: positionKey)
    }
}

struct PanelDragHandle: NSViewRepresentable {
    func makeNSView(context: Context) -> DragHandleView { DragHandleView() }
    func updateNSView(_ nsView: DragHandleView, context: Context) {}
}

final class DragHandleView: NSView {
    private var anchor: NSPoint?
    private var startingOrigin: NSPoint?
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setAccessibilityElement(true); setAccessibilityRole(.image)
        setAccessibilityLabel("Drag dictation panel")
        toolTip = "Drag to move. Voice remembers this position."
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseDown(with event: NSEvent) {
        guard let window else { return }
        anchor = window.convertPoint(toScreen: event.locationInWindow)
        startingOrigin = window.frame.origin
    }
    override func mouseDragged(with event: NSEvent) {
        guard let window, let anchor, let startingOrigin else { return }
        let point = window.convertPoint(toScreen: event.locationInWindow)
        window.setFrameOrigin(NSPoint(x: startingOrigin.x + point.x - anchor.x, y: startingOrigin.y + point.y - anchor.y))
    }
    override func mouseUp(with event: NSEvent) {
        (window?.windowController as? CapturePanelController)?.finishDragging()
        anchor = nil; startingOrigin = nil
    }
    override func resetCursorRects() { addCursorRect(bounds, cursor: .openHand) }
    override func draw(_ dirtyRect: NSRect) {
        NSColor.secondaryLabelColor.setFill()
        for x in [-3.0, 3.0] { for y in [-6.0, 0.0, 6.0] {
            NSBezierPath(ovalIn: NSRect(x: bounds.midX + x - 1.4, y: bounds.midY + y - 1.4, width: 2.8, height: 2.8)).fill()
        } }
    }
}

struct RecordingOverlay: View {
    @ObservedObject var model: AppModel
    var body: some View {
        HStack(spacing: 12) {
            PanelDragHandle().frame(width: 22, height: 56)
            VStack(alignment: .leading, spacing: 7) {
                Label(model.previewingPanel ? "Panel preview · microphone off" : model.phase == .recording ? "Capturing dictation" : model.phase == .cleaning ? "Tidying your words…" : "Transcribing…",
                      systemImage: model.phase == .recording ? "mic.fill" : "waveform")
                    .font(.system(size: 12, weight: .semibold)).lineLimit(1)
                HStack(spacing: 10) {
                    if model.phase == .recording {
                        WaveBars(level: model.level).frame(width: 94, height: 20)
                        Text(time(model.elapsed)).monospacedDigit()
                    } else if !model.previewingPanel { ProgressView().controlSize(.small) }
                    Text(model.previewingPanel ? "Drag the grip to place it anywhere" : model.phase == .recording ? "Click Finish when ready" : "Processing on your Mac")
                        .font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
                }.font(.system(size: 11))
            }.frame(maxWidth: .infinity, alignment: .leading)
            if model.previewingPanel {
                Button("Done") { model.closePanelPreview() }.buttonStyle(.borderedProminent)
            } else if model.phase == .recording {
                Button { model.stopRecording() } label: { Label("Finish", systemImage: "stop.fill") }
                    .buttonStyle(.borderedProminent).accessibilityLabel("Finish dictation")
            }
            if let id = model.shortcutRequest.id {
                Button { model.cancelShortcut(id) } label: { Image(systemName: "xmark.circle").font(.system(size: 19)).frame(width: 28, height: 32) }
                    .buttonStyle(.plain).accessibilityLabel("Cancel dictation").help("Discard this Shortcuts recording")
            } else { Menu {
                if model.phase == .recording { Button("Discard recording", role: .destructive) { model.cancelRecording() } }
                Button("Reset panel position") { model.onResetPanel?() }
                if model.previewingPanel { Button("Close preview") { model.closePanelPreview() } }
            } label: { Image(systemName: "ellipsis.circle").font(.system(size: 19)).frame(width: 28, height: 32) }
                .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                .accessibilityLabel("Dictation options").help("Dictation options") }
        }
        .padding(.horizontal, 12).frame(width: CapturePanelPlacement.size.width, height: CapturePanelPlacement.size.height)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(.primary.opacity(0.12)))
        .tint(Workbench.accent).workbenchTheme()
    }
}
