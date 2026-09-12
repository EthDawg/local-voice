import SwiftUI
import AppKit
import StageKit
import ServiceManagement

struct WorkbenchHome: View {
    @ObservedObject var model: AppModel
    @ObservedObject var stage: StageKitController
    @ObservedObject var keyboard: KeyboardCoachModel
    @State private var loginEnabled = SMAppService.mainApp.status == .enabled
    @State private var loginError: String?
    private let navItems: [(String, String, String)] = [
        ("home", "Home", "square.grid.2x2"), ("dictate", "Dictate", "mic"),
        ("speak", "Read aloud", "speaker.wave.2"), ("annotate", "Annotate", "pencil.tip"),
        ("present", "Present a device", "iphone"), ("history", "Recent transcripts", "clock"),
        ("library", "Saved resources", "square.stack"), ("shortcuts", "Keyboard", "keyboard"),
        ("models", "Models", "cpu"), ("settings", "Settings", "slider.horizontal.3")]
    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 5) {
                WorkbenchHeader(title: "Workbench", subtitle: "Everyday tools. A little less friction.", symbol: "square.stack.3d.up.fill")
                    .padding(.vertical, 20)
                ForEach(navItems, id: \.0) { page, title, symbol in
                    Button { keyboard.stopInteraction(); model.page = page } label: {
                        Label(title, systemImage: symbol).font(.system(size: 13, weight: model.page == page ? .semibold : .regular))
                            .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 12).padding(.vertical, 10)
                            .foregroundStyle(model.page == page ? Workbench.accent : .primary)
                            .background(model.page == page ? Workbench.accent.opacity(0.10) : .clear, in: RoundedRectangle(cornerRadius: 8))
                    }.buttonStyle(.plain)
                }
                Spacer()
                WorkbenchAppearancePicker().controlSize(.small)
                Text("PREVIEW · 2.0").font(.system(size: 10, design: .monospaced)).foregroundStyle(.secondary).padding(.top, 10)
            }.padding(16).frame(width: 215).background(Workbench.surface.opacity(0.6))
            Divider()
            Group {
                switch model.page {
                case "home": welcome
                case "annotate": stage.controlsView
                case "present": stage.scenesView
                case "shortcuts": KeyboardCoachView(model: keyboard)
                case "models": ScrollView { ModelSettingsView(engine: model.engine, isBusy: model.phase != .idle || model.preparing || model.rendering) { ready, message in
                    model.ready = ready; model.modelMessage = message
                }.padding(32) }
                case "settings": settings
                default: ContentView(model: model, embedded: true)
                }
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
        }.frame(minWidth: 1050, minHeight: 730).tint(Workbench.accent).workbenchTheme()
    }
    private var welcome: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                HStack {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Make room for the work.").font(.system(size: 34, weight: .semibold)).tracking(-0.7)
                        Text("Speak a thought. Explain a screen. Give your demo a stage.")
                            .font(.system(size: 15)).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "square.stack.3d.up.fill").font(.system(size: 42)).foregroundStyle(Workbench.accent)
                }.padding(.top, 16)
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {
                    card("Dictate", "A thought, ready to use.", "mic.fill", model.preferences.dictationShortcut.label) { model.page = "dictate" }
                    card("Read aloud", "Hear a draft. Save a reading.", "speaker.wave.2.fill", "Mac voices included") { model.page = "speak" }
                    card("Annotate", "Point, draw and return to your demo.", "pencil.tip.crop.circle", "Live screen tools") { model.page = "annotate" }
                    card("Present a device", "Your phone, ready for an audience.", "iphone", "Saved scenes and branding") { model.page = "present" }
                }
                HStack(spacing: 16) {
                    Image(systemName: "keyboard").font(.system(size: 30)).foregroundStyle(Workbench.accent)
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Find your rhythm.").font(.headline)
                        Text("See your shortcuts. Change a combination. Practise without starting a recording or drawing.")
                            .font(.callout).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Try the keyboard") { model.page = "shortcuts" }.buttonStyle(.bordered)
                }.padding(20).background(Workbench.surface, in: RoundedRectangle(cornerRadius: 14))
                HStack(alignment: .top, spacing: 24) {
                    Label("Free tools, no account needed", systemImage: "checkmark.seal")
                    Label("Your files stay yours", systemImage: "folder")
                    Label("One menu-bar home", systemImage: "menubar.rectangle")
                }.font(.caption).foregroundStyle(.secondary)
                if !model.ready {
                    HStack {
                        if model.preparing { ProgressView().controlSize(.small) }
                        Text(model.modelMessage).font(.callout)
                        Spacer()
                        Button("Speech settings") { model.page = "models" }
                    }.padding(16).background(.quaternary, in: RoundedRectangle(cornerRadius: 12))
                }
            }.padding(32)
        }
    }
    private func card(_ title: String, _ detail: String, _ symbol: String, _ footnote: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 12) {
                HStack { Image(systemName: symbol).font(.system(size: 25)).foregroundStyle(Workbench.accent); Spacer(); Image(systemName: "arrow.up.right").foregroundStyle(.tertiary) }
                Text(title).font(.system(size: 20, weight: .semibold))
                Text(detail).foregroundStyle(.secondary).font(.system(size: 13))
                Text(footnote).font(.system(size: 11, design: .monospaced)).foregroundStyle(Workbench.accent).padding(.top, 7)
            }.padding(22).frame(maxWidth: .infinity, minHeight: 154, alignment: .leading)
                .background(Workbench.surface, in: RoundedRectangle(cornerRadius: 16))
                .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Workbench.border))
        }.buttonStyle(.plain).accessibilityLabel(title + ". " + detail)
    }
    private var settings: some View {
        ScrollView { VStack(alignment: .leading, spacing: 22) {
            Text("Make yourself at home.").font(.largeTitle.weight(.semibold))
            Text("Only turn on the access you need. Closing this window leaves the menu-bar tools available; Quit stops Workbench.").foregroundStyle(.secondary)
            WorkbenchAppearancePicker()
            Toggle("Open Workbench at login", isOn: Binding(get: { loginEnabled }, set: { value in
                do { if value { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }; loginEnabled = SMAppService.mainApp.status == .enabled }
                catch { loginError = error.localizedDescription }
            }))
            if let loginError { Text(loginError).foregroundStyle(.orange) }
            Divider()
            VoiceOptions(model: model, showShortcut: false)
            Button("Your dictionary") { model.page = "dictionary" }
            Button("Position dictation panel…") { model.showPanelPreview() }.disabled(model.phase != .idle)
            Divider()
            Button("Models and local server") { model.page = "models" }
            Button("Keyboard and practice") { model.page = "shortcuts" }
            Text("Preview keeps its own session. Your previous Voice and StageMark data remains in place.").font(.caption).foregroundStyle(.secondary)
        }.padding(32).frame(maxWidth: .infinity, alignment: .leading) }
    }
}

struct WorkbenchQuickPanel: View {
    @ObservedObject var model: AppModel
    var open: (String) -> Void
    var draw: () -> Void
    var timer: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            WorkbenchHeader(title: "Workbench", subtitle: "A little less friction.", symbol: "square.stack.3d.up.fill")
            Button { model.onMenuRecording?() } label: {
                HStack { Label(model.phase == .recording ? "Finish dictation" : "Dictate", systemImage: model.phase == .recording ? "stop.fill" : "mic"); Spacer(); Text(model.preferences.dictationShortcut.label).font(.caption.monospaced()) }
            }.buttonStyle(.borderedProminent).controlSize(.large)
                .disabled(!model.ready || (model.phase != .idle && model.phase != .recording) || model.rendering)
            quick("Read aloud", "speaker.wave.2") { open("speak") }
            quick("Draw on screen", "pencil.tip") { draw() }
            quick("Present a device", "iphone") { open("present") }
            quick("Break timer", "timer") { timer() }
            Divider()
            HStack { Button("Open Workbench") { open("home") }; Spacer(); Button { open("shortcuts") } label: { Image(systemName: "keyboard") }.accessibilityLabel("Keyboard shortcuts") }
            Text(model.status).font(.caption).foregroundStyle(.secondary).lineLimit(2)
        }.padding(18).frame(width: 370).tint(Workbench.accent).workbenchTheme()
    }
    private func quick(_ title: String, _ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { Label(title, systemImage: symbol).frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 3) }.buttonStyle(.plain)
    }
}
