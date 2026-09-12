import AppKit
import AVFoundation
import Combine
import SwiftUI

/// Clicking Finish or Cancel leaves the destination application focused.
final class CapturePanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

final class CaptureHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

enum CapturePanelPlacement {
    static let size = NSSize(width: 480, height: 112)
    static func origin(saved: NSPoint?, screens: [NSRect], preferred: NSRect) -> NSPoint {
        let validSaved = saved.flatMap { $0.x.isFinite && $0.y.isFinite ? $0 : nil }
        let proposed = validSaved ?? NSPoint(x: preferred.maxX - size.width - 24, y: preferred.maxY - size.height - 32)
        let frame = screens.first { $0.contains(proposed) } ?? preferred
        let left = frame.minX + 8, bottom = frame.minY + 8
        return NSPoint(x: min(max(proposed.x, left), max(left, frame.maxX - size.width - 8)),
                       y: min(max(proposed.y, bottom), max(bottom, frame.maxY - size.height - 8)))
    }
}

@MainActor
final class CapturePanelController: NSWindowController, NSWindowDelegate {
    private let positionKey = "capturePanelOrigin.v1"
    private var positioning = false
    private var observations = Set<AnyCancellable>()
    init(model: AppModel) {
        let panel = CapturePanel(contentRect: NSRect(origin: .zero, size: CapturePanelPlacement.size),
                                 styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        super.init(window: panel)
        panel.title = "Workbench dictation"
        panel.isFloatingPanel = true; panel.level = .floating; panel.hidesOnDeactivate = false
        panel.isMovable = true
        panel.isOpaque = false; panel.backgroundColor = .clear; panel.hasShadow = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.contentView = CaptureHostingView(rootView: RecordingOverlay(model: model))
        panel.setContentSize(CapturePanelPlacement.size)
        panel.delegate = self
        // Published emits before assignment. Deliver on the next main-loop turn so
        // visibility reads the committed receipt state, including timer expiry.
        model.clipboardReceipt.$isHUDVisible.combineLatest(model.clipboardReceipt.$receipt)
            .receive(on: RunLoop.main)
            .sink { [weak self, weak model] _ in if let model { self?.update(model: model) } }
            .store(in: &observations)
        model.$phase.combineLatest(model.$captureFailure, model.$previewingPanel)
            .receive(on: RunLoop.main)
            .sink { [weak self, weak model] _ in if let model { self?.update(model: model) } }
            .store(in: &observations)
        NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.position() }
            .store(in: &observations)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    func update(model: AppModel) {
        guard let window else { return }
        let showsReceipt = model.clipboardReceipt.isHUDVisible && model.clipboardReceipt.receipt != nil
        if model.previewingPanel || model.phase != .idle || model.captureFailure != nil || showsReceipt {
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
        toolTip = "Drag to move. Workbench remembers this position."
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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    var body: some View {
        HStack(spacing: 10) {
            PanelDragHandle().frame(width: 28, height: 64)
            if model.phase == .idle && !model.previewingPanel, let failure = model.captureFailure {
                failureState(failure)
            } else if model.phase == .idle && !model.previewingPanel {
                CaptureReceiptView(receipts: model.clipboardReceipt, review: { model.onShowEditor?("history") }, resetPosition: { model.onResetPanel?() })
            } else {
                captureState
            }
        }.padding(.horizontal, 12)
            .frame(width: CapturePanelPlacement.size.width, height: CapturePanelPlacement.size.height)
            .background {
                if reduceTransparency { RoundedRectangle(cornerRadius: 18).fill(Color(nsColor: .windowBackgroundColor)) }
                else { RoundedRectangle(cornerRadius: 18).fill(.regularMaterial) }
            }
            .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(.primary.opacity(0.12)))
            .transaction { $0.animation = nil }
            .tint(Workbench.accent).workbenchTheme()
    }
    private var captureState: some View {
        HStack(spacing: 9) {
            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 7) {
                    Image(systemName: symbol).foregroundStyle(model.phase == .recording ? Color.red : Workbench.accent)
                    Text(title).font(.system(size: 12, weight: .semibold)).lineLimit(1)
                    if model.phase == .recording {
                        Spacer(minLength: 3)
                        Text("\(time(model.elapsed)) / 5:00").font(.system(size: 10, design: .monospaced)).monospacedDigit()
                            .accessibilityLabel("\(Int(model.elapsed)) seconds recorded, five minute limit")
                    }
                }
                if model.phase == .recording {
                    HStack(spacing: 7) {
                        CaptureLevelMeter(level: model.level).frame(width: 56, height: 12)
                        Text(model.isMicrophoneQuiet ? "Low microphone level" : "Microphone on")
                            .font(.system(size: 10)).foregroundStyle(model.isMicrophoneQuiet ? Color.orange : Color.secondary)
                    }
                } else if !model.previewingPanel && model.phase != .requesting {
                    HStack(spacing: 7) {
                        if !reduceMotion { ProgressView().controlSize(.mini) }
                        Text(model.captureProcessingLabel).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(2)
                    }
                }
                Text(instruction).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                if model.phase == .recording, model.elapsed >= 290 {
                    Text("Finishes automatically in \(max(0, Int(ceil(300 - model.elapsed))))s.")
                        .font(.system(size: 10)).foregroundStyle(.orange).monospacedDigit()
                } else if model.phase == .recording, let name = model.captureDestinationName {
                    Text("For \(name)").font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
                }
            }.frame(maxWidth: .infinity, alignment: .leading)
            VStack(spacing: 4) {
                if model.previewingPanel {
                    Button { model.closePanelPreview() } label: { Text("Done").frame(minWidth: 44, minHeight: 28) }.buttonStyle(.borderedProminent)
                } else {
                    if model.phase == .recording {
                        Button { model.stopRecording() } label: { Text("Finish").frame(minWidth: 44, minHeight: 28) }
                            .buttonStyle(.borderedProminent).accessibilityLabel("Finish dictation")
                    }
                    if model.canCancelCurrentCapture {
                        Button { model.cancelCurrentCapture() } label: { Text("Cancel").frame(minWidth: 44, minHeight: 28) }
                            .buttonStyle(.bordered).accessibilityLabel("Cancel dictation")
                    }
                }
            }.controlSize(.small)
            CapturePositionMenu(reset: { model.onResetPanel?() })
        }
    }
    private func failureState(_ failure: String) -> some View {
        HStack(spacing: 9) {
            VStack(alignment: .leading, spacing: 7) {
                Label("Dictation needs attention", systemImage: "exclamationmark.triangle")
                    .font(.system(size: 12, weight: .semibold)).foregroundStyle(.orange)
                Text(failure).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true).help(failure)
            }.frame(maxWidth: .infinity, alignment: .leading)
            VStack(spacing: 4) {
                if model.canRetry {
                    Button { model.retryTranscription() } label: { Text("Retry").frame(minWidth: 44, minHeight: 28) }
                        .buttonStyle(.borderedProminent).help("Retry the captured audio")
                } else {
                    Button { model.dismissCaptureFailure(); model.onShowEditor?("dictate") } label: {
                        Text("Open Workbench").font(.system(size: 10)).frame(minHeight: 28)
                    }.buttonStyle(.bordered)
                }
                Button { model.dismissCaptureFailure() } label: { Image(systemName: "xmark").frame(width: 28, height: 28) }
                    .buttonStyle(.plain).accessibilityLabel("Dismiss dictation error")
            }.controlSize(.small)
            CapturePositionMenu(reset: { model.onResetPanel?() })
        }
    }
    private var title: String {
        if model.previewingPanel { return "Panel preview · microphone off" }
        switch model.phase {
        case .requesting:
            switch AVCaptureDevice.authorizationStatus(for: .audio) {
            case .notDetermined: return "Allow microphone access"
            case .authorized: return "Starting microphone"
            case .denied, .restricted: return "Microphone access is off"
            @unknown default: return "Microphone permission needed"
            }
        case .recording: return "Recording"
        case .transcribing: return "Transcribing"
        case .cleaning: return "Tidying your words"
        case .delivering: return "Delivering text"
        case .cancelling: return "Cancelling"
        case .idle: return "Dictation"
        }
    }
    private var symbol: String {
        if model.previewingPanel { return "mic.slash" }
        switch model.phase {
        case .requesting: return "mic.badge.plus"
        case .recording: return "mic.fill"
        case .delivering: return "arrow.up.doc"
        default: return "waveform"
        }
    }
    private var instruction: String {
        if model.previewingPanel { return "Drag the grip to place it anywhere." }
        if model.phase == .requesting {
            switch AVCaptureDevice.authorizationStatus(for: .audio) {
            case .notDetermined: return "Respond to the macOS prompt, or choose Cancel."
            case .authorized: return "You can cancel before recording starts."
            default: return "Check Privacy & Security → Microphone in System Settings."
            }
        }
        if model.phase == .recording {
            let shortcut = model.preferences.dictationShortcut
            if shortcut.enabled && model.captureUsesHoldShortcut { return "Release \(shortcut.label) to finish." }
            if shortcut.enabled && model.preferences.capture == .toggle { return "\(shortcut.label) or Finish to stop." }
            return "Choose Finish when ready."
        }
        if model.phase == .delivering { return "Microphone off. Checking the destination." }
        if model.phase == .cancelling { return "Microphone off. Waiting for processing to stop." }
        if !model.canCancelCurrentCapture { return "Microphone off. Your original text is retained." }
        return "Microphone off. Cancel to stop processing."
    }
}

private struct CaptureLevelMeter: View {
    let level: Double
    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<8) { index in
                Capsule().fill(Double(index) / 8 < max(0, min(1, level)) ? Workbench.accent : Color.secondary.opacity(0.18))
            }
        }.accessibilityElement(children: .ignore).accessibilityLabel("Microphone level")
            .accessibilityValue(level < 0.05 ? "Quiet" : "Receiving sound")
    }
}

private struct CaptureReceiptView: View {
    @ObservedObject var receipts: ClipboardReceiptModel
    let review: () -> Void
    let resetPosition: () -> Void
    var body: some View {
        if let receipt = receipts.receipt {
            HStack(spacing: 9) {
                VStack(alignment: .leading, spacing: 7) {
                    HStack(spacing: 7) {
                        Image(systemName: receipt.symbolName).foregroundStyle(Workbench.accent)
                        Text(receipt.title).font(.system(size: 12, weight: .semibold)).lineLimit(1)
                        if receipt.wordCount > 0 { Text("\(receipt.wordCount) \(receipt.wordCount == 1 ? "word" : "words")").font(.system(size: 10)).foregroundStyle(.secondary) }
                    }
                    Text(receipt.detail).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                }.frame(maxWidth: .infinity, alignment: .leading)
                VStack(spacing: 3) {
                    Button { receipts.dismissHUD(); review() } label: { Text("Review").frame(minWidth: 44, minHeight: 28) }
                        .buttonStyle(.bordered).controlSize(.small).help("Open recent transcripts")
                    HStack(spacing: 2) {
                        if receipt.isClipboardCurrent {
                            Button { receipts.keepVisible.toggle() } label: {
                                Image(systemName: receipts.keepVisible ? "pin.fill" : "pin").frame(width: 28, height: 28)
                            }.buttonStyle(.plain)
                                .accessibilityLabel(receipts.keepVisible ? "Unpin receipt" : "Keep receipt visible")
                                .help("Keep visible while this text is on the clipboard")
                        }
                        Button { receipts.dismissHUD() } label: { Image(systemName: "xmark").frame(width: 28, height: 28) }
                            .buttonStyle(.plain).accessibilityLabel("Dismiss dictation receipt")
                    }
                }
                CapturePositionMenu(reset: resetPosition)
            }
        }
    }
}

private struct CapturePositionMenu: View {
    let reset: () -> Void
    var body: some View {
        Menu { Button("Reset panel position", action: reset) } label: {
            Image(systemName: "ellipsis").frame(width: 28, height: 32)
        }.menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
            .accessibilityLabel("Panel position options").help("Panel position options")
    }
}
