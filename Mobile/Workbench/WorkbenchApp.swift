import SwiftUI

@main struct WorkbenchMobileApp: App {
    @StateObject private var store: MobileStore
    @StateObject private var handoff: PhotoHandoffModel
    @StateObject private var speech = SpeechService()
    @StateObject private var reader = ReadingService()
    @Environment(\.scenePhase) private var scenePhase

    init() {
        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        let testing = arguments.contains("--ui-testing") || arguments.contains("--ui-testing-handoff")
        let root = testing ? FileManager.default.temporaryDirectory.appendingPathComponent("WorkbenchUITests-" + UUID().uuidString) : nil
        _store = StateObject(wrappedValue: MobileStore(directory: root))
        let handoffRoot = root ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Workbench", isDirectory: true)
        _handoff = StateObject(wrappedValue: PhotoHandoffModel(directory: handoffRoot.appendingPathComponent("PhotoHandoff", isDirectory: true),
                                                            platform: UIDevice.current.userInterfaceIdiom == .pad ? "iPad" : "iPhone", allowsCloudAccess: !testing))
        #else
        _store = StateObject(wrappedValue: MobileStore())
        let handoffRoot = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Workbench/PhotoHandoff", isDirectory: true)
        _handoff = StateObject(wrappedValue: PhotoHandoffModel(directory: handoffRoot, platform: UIDevice.current.userInterfaceIdiom == .pad ? "iPad" : "iPhone"))
        #endif
    }

    var body: some Scene {
        WindowGroup {
            MobileHome().environmentObject(store).environmentObject(speech).environmentObject(reader).environmentObject(handoff)
                .tint(Color.accentColor)
                .task { if handoff.isEnabled { await handoff.refresh() } }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active, handoff.isEnabled, !handoff.isBusy { Task { await handoff.refresh() } }
                }
                .alert("Could not complete that change", isPresented: Binding(get: { store.error != nil }, set: { if !$0 { store.error = nil } })) {
                    Button("OK", role: .cancel) { store.error = nil }
                } message: { Text(store.error ?? "") }
        }
    }
}

struct MobileHome: View {
    @EnvironmentObject private var store: MobileStore
    @EnvironmentObject private var reader: ReadingService
    @State private var about = false
    var body: some View {
        TabView {
            NavigationStack {
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        Text("Useful, wherever you are.").font(.title3).foregroundStyle(.secondary)
                        NavigationLink { MobileDictateView() } label: {
                            HStack(spacing: 18) {
                                Image(systemName: "mic.fill").font(.system(size: 32)).frame(width: 64, height: 72)
                                VStack(alignment: .leading, spacing: 5) {
                                    Text("Dictate").font(.title2.bold())
                                    Text("Speak. Review. Share.").font(.subheadline)
                                }
                                Spacer(minLength: 4); Image(systemName: "chevron.right").font(.subheadline.weight(.semibold))
                            }.padding(20).frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color.accentColor.opacity(0.10), in: RoundedRectangle(cornerRadius: 24))
                        }.buttonStyle(.plain).accessibilityIdentifier("tool.dictate")
                        ViewThatFits(in: .horizontal) {
                            HStack(spacing: 14) { readingCard; markupCard }
                            VStack(spacing: 14) { readingCard; markupCard }
                        }
                        VStack(spacing: 0) {
                            NavigationLink { MobileImageWorkspace(kind: .backdrop) } label: { toolRow("Backdrops", detail: "Prepare a picture for presenting", symbol: "rectangle.inset.filled") }
                            Divider().padding(.leading, 64)
                            NavigationLink { MobileImageWorkspace(kind: .wallpaper) } label: { toolRow("Wallpapers", detail: "Make a picture fit your screen", symbol: "photo") }.accessibilityIdentifier("tool.wallpaper")
                            Divider().padding(.leading, 64)
                            NavigationLink { PhotoHandoffView() } label: { toolRow("Take a photo for Mac", detail: "Keep a photo or send a private copy", symbol: "camera") }
                                .accessibilityIdentifier("tool.photoHandoff")
                        }.buttonStyle(.plain).padding(.horizontal, 16)
                            .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 24))
                        if !store.document.draft.isEmpty {
                            NavigationLink { MobileDictateView() } label: {
                                VStack(alignment: .leading, spacing: 8) {
                                    Label("Continue your draft", systemImage: "text.alignleft").font(.subheadline.bold())
                                    Text(store.document.draft).lineLimit(2).font(.subheadline).foregroundStyle(.secondary)
                                }.frame(maxWidth: .infinity, alignment: .leading).padding(18)
                            }.buttonStyle(.plain).background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20))
                        }
                    }.padding(20).frame(maxWidth: 720)
                }.frame(maxWidth: .infinity).background(Color(uiColor: .systemGroupedBackground))
                    .navigationTitle("Workbench")
                    .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("About Workbench", systemImage: "info.circle") { about = true }.labelStyle(.iconOnly) } }
            }.tabItem { Label("Tools", systemImage: "square.grid.2x2") }
            NavigationStack { MobileSavedView() }.tabItem { Label("Saved", systemImage: "folder") }
        }.modifier(MobileReadingAccessory()).sheet(isPresented: $about) { MobileAboutView() }
    }

    private var readingCard: some View {
        NavigationLink { MobileReadingView() } label: { smallCard("Read aloud", detail: "Listen to your text", symbol: "speaker.wave.2") }
            .buttonStyle(.plain).accessibilityIdentifier("tool.read")
    }
    private var markupCard: some View {
        NavigationLink { MobileImageWorkspace(kind: .markup) } label: { smallCard("Mark up", detail: "Explain a screenshot", symbol: "pencil.tip.crop.circle") }
            .buttonStyle(.plain).accessibilityIdentifier("tool.markup")
    }
    private func smallCard(_ title: String, detail: String, symbol: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Image(systemName: symbol).font(.title2).foregroundStyle(Color.accentColor).frame(width: 48, height: 48)
                .background(Color.accentColor.opacity(0.09), in: Circle())
            Text(title).font(.headline); Text(detail).font(.subheadline).foregroundStyle(.secondary)
        }.frame(minWidth: 120, maxWidth: .infinity, minHeight: 130, alignment: .topLeading).padding(20)
            .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 24))
    }
    private func toolRow(_ title: String, detail: String, symbol: String) -> some View {
        HStack(spacing: 14) {
            Image(systemName: symbol).font(.title3).foregroundStyle(Color.accentColor).frame(width: 34)
            VStack(alignment: .leading, spacing: 3) { Text(title).font(.headline); Text(detail).font(.subheadline).foregroundStyle(.secondary) }
            Spacer(minLength: 0); Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
        }.padding(.vertical, 20).contentShape(Rectangle())
    }
}

/// The iOS 26.0 accessory reserves space even when its content is empty.
/// Keep one stable TabView and use the explicit visibility API where available.
private struct MobileReadingAccessory: ViewModifier {
    @EnvironmentObject private var reader: ReadingService
    private var active: Bool { reader.isSpeaking || reader.isPaused }
    @ViewBuilder func body(content: Content) -> some View {
        if #available(iOS 26.1, *) {
            content.tabViewBottomAccessory(isEnabled: active) { controls }
        } else {
            content.safeAreaInset(edge: .bottom, spacing: 0) {
                if active { controls.background(.regularMaterial) }
            }
        }
    }
    private var controls: some View {
        HStack {
            Label(reader.isPaused ? "Reading paused" : "Reading", systemImage: "speaker.wave.2").font(.subheadline)
            Spacer()
            Button(reader.isPaused ? "Resume" : "Pause", systemImage: reader.isPaused ? "play.fill" : "pause.fill") { reader.pauseResume() }
                .labelStyle(.iconOnly).frame(minWidth: 44, minHeight: 44)
            Button("Stop reading", systemImage: "stop.fill") { reader.stop() }
                .labelStyle(.iconOnly).frame(minWidth: 44, minHeight: 44)
        }.padding(.horizontal, 18)
    }
}

struct MobileAboutView: View {
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            List {
                Section {
                    Label("Workbench Preview", systemImage: "square.grid.2x2.fill").font(.headline)
                    Text("Native utilities for your own words and pictures. Everyday tools work without a Workbench account.")
                }
                Section("On this device") {
                    Text("Your drafts, saved text and original pictures stay in Workbench’s local storage. Share sends only the item you choose to the destination you select.")
                    Text("Dictation uses Apple’s on-device speech model. Preparing a language can download system assets. Reading uses installed Apple voices.")
                    Text("Pictures are exported as copies. Apple’s Wallpaper settings and meeting apps remain in control of installation and sharing.")
                }
                Section("Photo handoff") {
                    PhotoHandoffSettingsView()
                }
                Section("Preview boundaries") {
                    Text("Saved work does not automatically sync with the Mac. Optional photo handoff sends only the photos you choose, using your private iCloud. This Preview has no custom keyboard, cross-app overlays or background microphone.")
                    Text("Original image assets are retained when you delete a saved project. Deleting the app removes its local library; export important work first.")
                    Link("Mobile guide", destination: URL(string: "https://workbench-mac.vercel.app/mobile/")!)
                    Link("Source and feedback", destination: URL(string: "https://github.com/EthDawg/local-voice")!)
                }
            }.navigationTitle("About").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }
}
