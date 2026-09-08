import AppKit
import SwiftUI

struct ShortcutControl: View {
    @ObservedObject var model: AppModel
    var id: UInt32
    var title: String
    var shortcut: VoiceShortcut { id == 1 ? model.preferences.dictationShortcut : model.preferences.controlsShortcut }
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(title); Spacer()
                Button(model.editingShortcut == id ? "Press keys…" : shortcut.label) { model.onEditShortcut?(id) }
                    .font(.system(size: 11, design: .monospaced)).frame(minWidth: 84)
                    .accessibilityLabel("Edit \(title.lowercased()) shortcut")
            }
            if model.editingShortcut == id { Text("Use ⌃, ⌥ or ⌘ with a key. Esc cancels; Delete turns it off.").font(.caption).foregroundStyle(.secondary) }
            if let failure = model.shortcutFailures[id] { Text(failure).font(.caption).foregroundStyle(.orange) }
        }
    }
}
struct VoiceOptions: View {
    @ObservedObject var model: AppModel
    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            ShortcutControl(model: model, id: 1, title: "Dictation")
            Picker("Activation", selection: $model.preferences.capture) {
                ForEach(CaptureMode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            Picker("Cleanup", selection: $model.preferences.cleanup) {
                ForEach(CleanupStyle.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            Text(model.preferences.cleanup.detail).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Picker("Delivery", selection: $model.preferences.delivery) {
                ForEach(DeliveryMode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            if model.preferences.delivery == .paste {
                if model.accessibilityGranted {
                    Label("Automatic paste ready", systemImage: "checkmark.circle").foregroundStyle(Workbench.accent).font(.caption)
                } else {
                    Button("Enable automatic paste…") { model.requestAccessibility() }
                    Text("Allow Accessibility once. Until then, your transcript is copied.").font(.caption).foregroundStyle(.secondary)
                }
            }
        }.disabled(model.phase != .idle)
    }
}
struct VoiceQuickControls: View {
    static let size = NSSize(width: 370, height: 650)
    @ObservedObject var model: AppModel
    var body: some View {
        VStack(spacing: 12) {
            HStack {
                WorkbenchHeader(title: "Voice", subtitle: model.ready ? "Ready for your next thought" : "Preparing local speech…", symbol: "waveform")
                Spacer()
                Menu {
                    Button("Open editor…") { model.onShowEditor?("dictate") }
                    Button("Recent transcripts…") { model.onShowEditor?("history") }
                    Button("Your dictionary…") { model.onShowEditor?("dictionary") }
                    Divider()
                    Button("Quit Workbench Voice") { NSApp.terminate(nil) }
                } label: { Image(systemName: "ellipsis.circle").font(.system(size: 18)) }
                    .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize().accessibilityLabel("More options")
            }
            Picker("Quick controls", selection: $model.quickTab) {
                ForEach(["Dictate", "Read", "General"], id: \.self) { Text($0).tag($0) }
            }.pickerStyle(.segmented).labelsHidden()
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if let error = model.error {
                        HStack(alignment: .top) { Text(error); Spacer(); Button { model.error = nil } label: { Image(systemName: "xmark") } }
                            .font(.caption).foregroundStyle(.orange)
                    }
                    switch model.quickTab {
                    case "Read": reading
                    case "General": general
                    default: dictation
                    }
                }.frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 2)
            }
            Divider()
            Text(model.status).font(.system(size: 10)).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading).lineLimit(3)
            HStack {
                Button("Open editor…") { model.onShowEditor?(model.quickTab == "Read" ? "speak" : "dictate") }.buttonStyle(.link)
                Spacer()
                WorkbenchSwitcher { model.onCloseMenu?(); model.stopPlayback() }.disabled(model.phase != .idle)
            }
        }.padding(14).frame(width: Self.size.width, height: Self.size.height)
            .font(.system(size: 12)).controlSize(.small).background(Workbench.background).tint(Workbench.accent).workbenchTheme()
            .onExitCommand { model.onCloseMenu?() }
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in model.refreshPermissions() }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Workbench Voice quick controls")
    }
    private var dictation: some View {
        VStack(alignment: .leading, spacing: 14) {
            Button { model.onMenuRecording?() } label: {
                HStack { Image(systemName: model.phase == .recording ? "stop.fill" : "mic.fill"); Text(model.phase == .recording ? "Finish dictation" : "Start dictation"); Spacer(); Text(model.phase == .recording ? time(model.elapsed) : model.preferences.dictationShortcut.label).font(.caption) }
                    .padding(.vertical, 8).frame(maxWidth: .infinity)
            }.buttonStyle(.borderedProminent).disabled(!model.ready || (model.phase != .idle && model.phase != .recording) || model.rendering)
            if model.phase == .requesting { Button("Cancel microphone request") { model.cancelRecording() } }
            VoiceOptions(model: model)
            Divider()
            if !model.transcript.isEmpty {
                HStack { Text("LAST TRANSCRIPT").font(.system(size: 9, weight: .semibold)).foregroundStyle(.secondary); Spacer(); Button("Copy") { model.copyTranscript() }.buttonStyle(.link) }
                Text(model.transcript).font(.system(size: 11)).lineLimit(5).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                HStack {
                    Button("Edit / original…") { model.onShowEditor?("dictate") }
                    Spacer()
                    Button("Paste last transcript") { model.onPasteLast?() }.disabled(model.phase != .idle)
                }
            } else { Text("Start in any text field. Your words return there when you finish.").font(.caption).foregroundStyle(.secondary) }
        }
    }
    private var reading: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Give your eyes a break.").font(.headline)
            Button("Read clipboard") {
                if let text = NSPasteboard.general.string(forType: .string), !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    model.speechText = text; model.listen()
                } else { model.status = "Copy some text first." }
            }.disabled(model.phase != .idle || model.rendering || model.playing || model.paused)
            Picker("Voice", selection: $model.voice) { ForEach(model.voices, id: \.self) { Text($0).tag($0) } }
            HStack { Text("Pace"); Slider(value: $model.rate, in: 100...300, step: 5); Text("\(Int(model.rate))").monospacedDigit() }
            Text(model.speechText.isEmpty ? "Paste or type a longer passage in the editor." : model.speechText).lineLimit(9).foregroundStyle(.secondary)
            HStack {
                Button(model.playing ? "Pause" : model.paused ? "Resume" : "Listen") { model.listen() }.disabled(model.speechText.isEmpty || model.rendering || model.phase != .idle)
                if model.playing || model.paused { Button("Stop") { model.stopPlayback() } }
                Spacer(); Button("Edit text…") { model.onShowEditor?("speak") }
            }
            Text("Installed Mac voices. No account or usage meter.").font(.caption).foregroundStyle(.secondary)
        }
    }
    private var general: some View {
        VStack(alignment: .leading, spacing: 16) {
            ShortcutControl(model: model, id: 2, title: "Quick controls")
            Toggle("Restore clipboard after confirmed paste", isOn: $model.preferences.restoreClipboard)
            Text("If focus changes or paste cannot be confirmed, the transcript stays on your clipboard.").font(.caption).foregroundStyle(.secondary)
            Divider(); WorkbenchAppearancePicker()
            Text("One appearance for Voice and StageMark. Search Workbench in Spotlight to find your tools.").font(.caption).foregroundStyle(.secondary)
            Divider()
            Label(model.modelMessage, systemImage: "cpu").font(.caption)
            Text(CleanupEngine.availability).font(.caption).foregroundStyle(.secondary)
            if !model.ready && !model.preparing { Button("Retry model") { Task { await model.prepare() } } }
            Button("All settings…") { model.onShowEditor?("settings") }
        }
    }
}
