import SwiftUI

@main struct WorkbenchMobileApp: App {
    @UIApplicationDelegateAdaptor(MobileApplicationDelegate.self) private var appDelegate
    @StateObject private var scenes: SceneLibraryModel
    @StateObject private var store: MobileStore
    @StateObject private var handoff: PhotoHandoffModel
    @StateObject private var speech = SpeechService()
    @StateObject private var reader = ReadingService()
    @Environment(\.scenePhase) private var scenePhase

    init() {
        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        let testing = arguments.contains("--ui-testing") || arguments.contains("--ui-testing-handoff")
        #else
        let testing = false
        #endif
        let root = testing ? FileManager.default.temporaryDirectory.appendingPathComponent("WorkbenchUITests-" + UUID().uuidString)
            : FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Workbench", isDirectory: true)
        _store = StateObject(wrappedValue: MobileStore(directory: root))
        _handoff = StateObject(wrappedValue: PhotoHandoffModel(directory: root.appendingPathComponent("PhotoHandoff", isDirectory: true),
            platform: UIDevice.current.userInterfaceIdiom == .pad ? "iPad" : "iPhone", allowsCloudAccess: !testing))
        let cloud = PhotoCloudConfiguration.current()
        _scenes = StateObject(wrappedValue: SceneLibraryModel(directory: root.appendingPathComponent("Scenes", isDirectory: true),
            configuration: SceneCloudConfiguration(container: cloud.container, environment: cloud.environment, isProvisioned: !testing && cloud.isConfigured)))
    }

    var body: some Scene {
        WindowGroup {
            MobileHome().environmentObject(store).environmentObject(speech).environmentObject(reader).environmentObject(handoff).environmentObject(scenes)
                .tint(Color.accentColor)
                .task {
                    if handoff.isEnabled { await handoff.refresh() }
                    if scenes.isEnabled { await scenes.refresh() }
                }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active {
                        if handoff.isEnabled, !handoff.isBusy { Task { await handoff.refresh() } }
                        if scenes.isEnabled, !scenes.isBusy { Task { await scenes.refresh() } }
                    } else if phase == .background {
                        scenes.cancelRefresh()
                    }
                }
                .alert("Could not complete that change", isPresented: Binding(get: { store.error != nil }, set: { if !$0 { store.error = nil } })) {
                    Button("OK", role: .cancel) { store.error = nil }
                } message: { Text(store.error ?? "") }
        }
    }
}

struct MobileHome: View {
    @EnvironmentObject private var store: MobileStore
    @EnvironmentObject private var scenes: SceneLibraryModel
    @EnvironmentObject private var reader: ReadingService
    @State private var about = false
    @State private var selectedTab = 0
    @State private var path: [HomeRoute] = []
    @State private var sceneFileError: String?
    @ObservedObject private var quickActions = MobileQuickActionRouter.shared
    @ObservedObject private var sceneEditing = SceneEditingActivity.shared
    @Environment(\.scenePhase) private var scenePhase
    private enum HomeRoute: Hashable { case dictate, captureScene, scene(UUID) }

    var body: some View {
        TabView(selection: $selectedTab) {
            NavigationStack(path: $path) {
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
                            NavigationLink { MobileScenesView() } label: { toolRow("Scenes", detail: "Prepare here. Present on your Mac.", symbol: "rectangle.inset.filled") }.accessibilityIdentifier("tool.scenes")
                            Divider().padding(.leading, 64)
                            NavigationLink { MobileImageWorkspace(kind: .wallpaper) } label: { toolRow("Wallpapers", detail: "Make a picture fit your screen", symbol: "photo") }.accessibilityIdentifier("tool.wallpaper")
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
                    .toolbar(.visible, for: .tabBar)
                    .navigationDestination(for: HomeRoute.self) { route in
                        switch route {
                        case .dictate: MobileDictateView()
                        case .captureScene: MobileScenesView(captureOnOpen: true)
                        case .scene(let id): MobileSceneEditor(sceneID: id)
                        }
                    }
                    .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("About Workbench", systemImage: "info.circle") { about = true }.labelStyle(.iconOnly) } }
            }.tabItem { Label("Tools", systemImage: "square.grid.2x2") }.tag(0)
            NavigationStack { MobileSavedView().toolbar(.visible, for: .tabBar) }.tabItem { Label("Saved", systemImage: "folder") }.tag(1)
        }.modifier(MobileReadingAccessory()).sheet(isPresented: $about) { MobileAboutView() }
            .onOpenURL { url in
                guard !sceneEditing.hasUnsavedEdits else {
                    sceneFileError = "Save your scene first, then open this file again. Your current edits are still here."
                    return
                }
                let access = url.startAccessingSecurityScopedResource()
                defer { if access { url.stopAccessingSecurityScopedResource() } }
                do {
                    let copy = try scenes.importPackage(SceneFile.read(url))
                    selectedTab = 0; path = [.scene(copy.id)]
                } catch { sceneFileError = error.localizedDescription }
            }
            .alert("Could not open scene", isPresented: Binding(get: { sceneFileError != nil }, set: { if !$0 { sceneFileError = nil } })) {
                Button("OK", role: .cancel) { sceneFileError = nil }
            } message: { Text(sceneFileError ?? "") }
            .onChange(of: quickActions.pending) { _, _ in handleQuickAction() }
            .onChange(of: sceneEditing.hasUnsavedEdits) { _, hasEdits in if !hasEdits { handleQuickAction() } }
            .onChange(of: scenePhase) { _, phase in if phase == .active { handleQuickAction() } }
            .task { handleQuickAction() }
    }

    private func handleQuickAction() {
        guard !sceneEditing.hasUnsavedEdits,
              let action = quickActions.take(isActive: scenePhase == .active) else { return }
        selectedTab = 0; about = false
        path = [action == .dictate ? .dictate : .captureScene]
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
                    Text("Personal scene sync is optional and uses the same Apple Account on your devices. Drafts, recordings, markup and wallpaper projects stay local. The separate photo inbox sends only photos you choose. This Preview has no custom keyboard, cross-app overlays or background microphone.")
                    Text("Original image assets are retained when you delete a saved project. Deleting the app removes its local library; export important work first.")
                    Link("Privacy Policy", destination: URL(string: "https://workbench-mac.vercel.app/privacy.html")!)
                        .accessibilityIdentifier("about.privacyPolicy")
                    Link("Mobile guide", destination: URL(string: "https://workbench-mac.vercel.app/mobile/")!)
                    Link("Source and feedback", destination: URL(string: "https://github.com/EthDawg/workbench")!)
                }
            }.navigationTitle("About").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }
}
