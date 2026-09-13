import SwiftUI

struct MobileSavedView: View {
    @EnvironmentObject private var store: MobileStore
    @EnvironmentObject private var handoff: PhotoHandoffModel
    @EnvironmentObject private var sceneLibrary: SceneLibraryModel
    @State private var query = ""
    @State private var filter = "All"
    @State private var deleting: UUID?
    @State private var deletingText = false
    private var texts: [MobileText] {
        store.document.texts.filter { query.isEmpty || ($0.title + $0.text + $0.original).localizedStandardContains(query) }.sorted { $0.modified > $1.modified }
    }
    private var images: [MobileImageProject] {
        store.document.images.filter { query.isEmpty || ($0.title + $0.kind.title + $0.caption).localizedStandardContains(query) }.sorted { $0.modified > $1.modified }
    }
    private var handoffPhotos: [HandoffPhoto] {
        handoff.photos.filter { query.isEmpty || ($0.title + " " + $0.sourceDevice).localizedStandardContains(query) }
    }
    private var scenes: [SavedSceneRecord] {
        sceneLibrary.records.filter { !$0.isDeleted && (query.isEmpty || $0.scene.name.localizedStandardContains(query)) }
    }
    var body: some View {
        List {
            Picker("Show", selection: $filter) { ForEach(["All", "Text", "Pictures"], id: \.self) { Text($0) } }.pickerStyle(.segmented).listRowBackground(Color.clear).listRowInsets(EdgeInsets())
            if filter != "Text", !scenes.isEmpty {
                Section("Scenes") {
                    ForEach(scenes) { record in
                        NavigationLink { MobileSceneEditor(sceneID: record.id) } label: {
                            HStack(spacing: 14) {
                                SceneThumbnail(scene: record.scene, store: sceneLibrary).frame(width: 86, height: 56).clipped()
                                    .clipShape(RoundedRectangle(cornerRadius: 9))
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(record.scene.name).font(.headline)
                                    Text(sceneStatus(record)).font(.caption).foregroundStyle(.secondary)
                                }
                            }.padding(.vertical, 4)
                        }
                    }
                }
            }
            if filter != "Pictures", !texts.isEmpty {
                Section("Text") {
                    ForEach(texts) { record in
                        NavigationLink { MobileTextDetail(record: record) } label: {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(record.title).font(.headline).lineLimit(2)
                                Text(record.modified, style: .date).font(.caption).foregroundStyle(.secondary)
                            }.padding(.vertical, 6)
                        }.swipeActions { Button("Delete", role: .destructive) { deleting = record.id; deletingText = true } }
                    }
                }
            }
            if filter != "Text", !images.isEmpty {
                Section("Pictures") {
                    ForEach(images) { record in
                        NavigationLink { MobileImageWorkspace(kind: record.kind, projectID: record.id) } label: {
                            HStack(spacing: 14) {
                                if let image = store.image(record, maxPixels: 180) { Image(uiImage: image).resizable().scaledToFill().frame(width: 64, height: 64).clipped().clipShape(RoundedRectangle(cornerRadius: 12)).accessibilityHidden(true) }
                                else { Image(systemName: "photo").frame(width: 64, height: 64).foregroundStyle(.secondary) }
                                VStack(alignment: .leading, spacing: 6) { Text(record.title).font(.headline).lineLimit(2); Text(record.kind.title).font(.caption).foregroundStyle(.secondary) }
                            }.padding(.vertical, 4)
                        }.swipeActions { Button("Delete", role: .destructive) { deleting = record.id; deletingText = false } }
                    }
                }
            }
            if filter != "Text", !handoffPhotos.isEmpty {
                Section("Photo handoff") {
                    ForEach(handoffPhotos) { photo in
                        NavigationLink { PhotoHandoffDetailView(photoID: photo.id) } label: { PhotoHandoffRow(photo: photo) }
                    }
                }
            }
        }.navigationTitle("Saved").searchable(text: $query, prompt: "Find your words and pictures")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink { PhotoHandoffView() } label: { Label("Photo handoff", systemImage: "camera") }
                        .accessibilityIdentifier("saved.photoHandoff")
                }
            }
            .overlay {
                if (filter == "Pictures" || texts.isEmpty) && (filter == "Text" || (images.isEmpty && handoffPhotos.isEmpty && scenes.isEmpty)) {
                    ContentUnavailableView(query.isEmpty ? "Your useful things, kept." : "Nothing found", systemImage: query.isEmpty ? "folder" : "magnifyingglass", description: Text(query.isEmpty ? "Save text, a scene, marked screenshot or wallpaper. It will be here when you need it." : "Try a different word." )).padding(.top, 70).allowsHitTesting(false)
                }
            }
            .confirmationDialog("Delete this saved item?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }), titleVisibility: .visible) {
                Button("Delete saved item", role: .destructive) { if let id = deleting { if deletingText { store.deleteText(id) } else { store.deleteImage(id) } }; deleting = nil }
            } message: { Text("Other saved work and exported copies are unchanged.") }
    }
}

struct MobileTextDetail: View {
    @EnvironmentObject private var store: MobileStore
    @EnvironmentObject private var reader: ReadingService
    let record: MobileText
    @State private var text: String
    @State private var notice: String?
    @State private var listening = false
    init(record: MobileText) { self.record = record; _text = State(initialValue: record.text) }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                TextEditor(text: $text).frame(minHeight: 240).padding(10).background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20)).accessibilityLabel("Saved text")
                HStack {
                    ShareLink(item: text) { Label("Share", systemImage: "square.and.arrow.up").frame(maxWidth: .infinity, minHeight: 36) }.buttonStyle(.borderedProminent)
                    Button("Copy", systemImage: "doc.on.doc") { UIPasteboard.general.string = text; notice = "Copied." }.buttonStyle(.bordered)
                }
                Button("Read aloud", systemImage: "speaker.wave.2") { if store.change({ $0.readText = text }) { reader.stop(); listening = true } }.frame(minHeight: 44)
                DisclosureGroup("Original") { Text(record.original).frame(maxWidth: .infinity, alignment: .leading).textSelection(.enabled).padding(.top, 8) }
                if let asset = record.audioAsset, let url = store.disk.assetURL(asset), FileManager.default.fileExists(atPath: url.path) { ShareLink(item: url) { Label("Share original audio", systemImage: "waveform") }.frame(minHeight: 44) }
                if let notice { Text(notice).font(.footnote).foregroundStyle(.secondary) }
            }.padding(20).frame(maxWidth: 720)
        }.frame(maxWidth: .infinity).background(Color(uiColor: .systemGroupedBackground)).navigationTitle("Saved text").navigationBarTitleDisplayMode(.inline)
            .toolbar(.hidden, for: .tabBar)
            .onChange(of: text) { _, value in
                guard value.count <= 50_000 else { text = String(value.prefix(50_000)); return }
                if !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { _ = store.saveText(value, original: record.original, id: record.id) }
            }
            .navigationDestination(isPresented: $listening) { MobileReadingView() }
    }
}
