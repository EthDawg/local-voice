import SwiftUI

struct PersonaLibraryView: View {
    @ObservedObject var library: PersonaLibrary
    var onChoose: ((SavedPersona) -> Void)? = nil
    @Environment(\.dismiss) private var dismiss
    @State private var renaming: UUID?
    @State private var name = ""
    @State private var groupName = ""
    @State private var creatingGroup = false
    @State private var renamingGroup = false
    @State private var editingGroup: PersonaGroup?
    @State private var editingCard: SavedPersona?
    @State private var choosingStarter = false
    @State private var starterToEdit: SavedPersona?
    @State private var showAfterDismiss = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Personas").font(.title2.bold())
                Spacer()
                Menu("Add persona") {
                    Button("Choose a starter portrait…") { library.hideOverlay(); choosingStarter = true }
                    Divider()
                    Button("Import portrait for an editable card…") {
                        library.hideOverlay()
                        library.importImage(card: PersonaCardStyle()) { editingCard = $0 }
                    }
                    Button("Import finished card…") { library.importImage() }
                    Button("Paste finished image") { library.pasteImage() }
                }.disabled(library.isReadOnly)
                Button("Done") { dismiss() }.keyboardShortcut(.cancelAction)
            }
            Text("Prepare a group before presenting. Floating controls show only its members; customer group names stay here.")
                .font(.callout).foregroundStyle(.secondary)
            HStack {
                Picker("Group", selection: Binding(get: { library.activeGroupID }, set: { library.prepareGroup($0) })) {
                    Text("All saved · no live switching").tag(UUID?.none)
                    ForEach(library.groups) { group in Text(group.name).tag(Optional(group.id)) }
                }.disabled(library.isReadOnly)
                Button("New…") { library.hideOverlay(); groupName = ""; creatingGroup = true }.disabled(library.isReadOnly)
                    .accessibilityLabel("Create persona group")
                if let group = library.activeGroup {
                    Menu("Edit group") {
                        Button("Choose members…") { library.hideOverlay(); editingGroup = group }
                        Button("Rename…") { library.hideOverlay(); groupName = group.name; renamingGroup = true }
                        Button("Remove group", role: .destructive) { library.removeGroup(group.id) }
                    }.disabled(library.isReadOnly)
                }
            }
            HStack(alignment: .top, spacing: 20) {
                List(selection: $library.selectedID) {
                    ForEach(library.visibleItems) { persona in
                        HStack(spacing: 10) {
                            thumbnail(persona, width: 52, height: 54)
                            Text(persona.name).lineLimit(2)
                        }.padding(.vertical, 4).tag(persona.id)
                            .contextMenu {
                                Button("Rename library item…") { library.hideOverlay(); renaming = persona.id; name = persona.name }.disabled(library.isReadOnly)
                                Button("Remove from saved personas") { library.remove(persona.id) }.disabled(library.isReadOnly)
                                if let group = library.activeGroup, let index = group.personaIDs.firstIndex(of: persona.id) {
                                    Divider()
                                    Button("Move earlier") { library.moveMember(persona.id, by: -1) }.disabled(library.isReadOnly || index == 0)
                                    Button("Move later") { library.moveMember(persona.id, by: 1) }.disabled(library.isReadOnly || index == group.personaIDs.count - 1)
                                }
                            }
                    }
                }.frame(width: 250, height: 360).overlay {
                    if library.visibleItems.isEmpty {
                        VStack(spacing: 10) {
                            Text(library.activeGroup == nil ? "Your saved personas appear here." : "Choose this group's members.")
                                .multilineTextAlignment(.center).foregroundStyle(.secondary)
                            if let group = library.activeGroup {
                                Button("Choose members…") { editingGroup = group }.disabled(library.isReadOnly)
                            }
                        }.padding()
                    }
                }
                VStack(alignment: .leading, spacing: 12) {
                    if let selected = library.selected {
                        thumbnail(selected, width: 265, height: 155)
                            .frame(maxWidth: .infinity)
                        Text(selected.name).font(.headline).lineLimit(2)
                        if selected.card != nil {
                            Button("Edit visible label and colour…") { library.hideOverlay(); editingCard = selected }.disabled(library.isReadOnly)
                        } else {
                            Text("Finished artwork stays as imported. For editable text and colour, add a portrait without baked labels.")
                                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                        }
                        HStack {
                            Button(library.overlayVisible ? "Hide floating persona" : "Show over browser") {
                                if library.overlayVisible { library.hideOverlay() }
                                else { showAfterDismiss = true; dismiss() }
                            }.disabled(library.renderedImage(for: selected) == nil)
                            if let onChoose {
                                Button("Use in scene") { onChoose(selected); dismiss() }
                                    .disabled(library.renderedImage(for: selected) == nil)
                            }
                        }
                        Toggle("Lock artwork · clicks pass through", isOn: Binding(
                            get: { library.overlayLocked }, set: { library.setOverlayLocked($0) }))
                        HStack(spacing: 8) {
                            Text("Size")
                            Slider(value: Binding(get: { library.overlayWidth }, set: { library.setOverlayWidth($0) }), in: 0.06...0.40)
                                .accessibilityLabel("Floating persona size")
                            Menu("Position") {
                                Button("Top left") { library.setOverlayPosition(x: 0.02, y: 0.98) }
                                Button("Top centre") { library.setOverlayPosition(x: 0.5, y: 0.98) }
                                Button("Top right") { library.setOverlayPosition(x: 0.98, y: 0.98) }
                                Divider()
                                Button("Left centre") { library.setOverlayPosition(x: 0.02, y: 0.5) }
                                Button("Right centre") { library.setOverlayPosition(x: 0.98, y: 0.5) }
                                Divider()
                                Button("Bottom left") { library.setOverlayPosition(x: 0.02, y: 0.02) }
                                Button("Bottom centre") { library.setOverlayPosition(x: 0.5, y: 0.02) }
                                Button("Bottom right") { library.setOverlayPosition(x: 0.98, y: 0.02) }
                            }.fixedSize()
                        }
                        if let group = library.activeGroup, let index = group.personaIDs.firstIndex(of: selected.id) {
                            HStack {
                                Text("Group order \(index + 1) of \(group.personaIDs.count)").font(.caption).foregroundStyle(.secondary)
                                Spacer()
                                Button { library.moveMember(selected.id, by: -1) } label: { Image(systemName: "arrow.up") }
                                    .accessibilityLabel("Move earlier in group").disabled(library.isReadOnly || index == 0)
                                Button { library.moveMember(selected.id, by: 1) } label: { Image(systemName: "arrow.down") }
                                    .accessibilityLabel("Move later in group").disabled(library.isReadOnly || index == group.personaIDs.count - 1)
                            }
                        }
                        if library.overlayVisible, library.liveSelection != nil {
                            Button("Focus floating controls for keyboard") { library.focusOverlayControls() }
                        }
                    } else {
                        Image(systemName: "person.crop.rectangle.stack").font(.system(size: 38)).foregroundStyle(.secondary)
                        Text("Choose or import a persona").font(.headline)
                        Text("Use the same saved image over your browser or inside a mobile scene.")
                            .font(.callout).foregroundStyle(.secondary)
                    }
                }.frame(width: 320, alignment: .leading)
            }
            if let notice = library.notice {
                Text(notice).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Text("Whole-screen sharing includes the floating artwork and its controls. Use a persona in a scene when sharing that presentation window.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }.padding(24).frame(width: 660).background(Workbench.background).workbenchTheme()
            .onDisappear {
                guard showAfterDismiss else { return }
                showAfterDismiss = false
                library.showOverlay()
            }
            .sheet(item: $editingCard) { PersonaCardEditor(library: library, persona: $0) }
            .sheet(isPresented: $choosingStarter, onDismiss: {
                if let persona = starterToEdit { starterToEdit = nil; editingCard = persona }
            }) {
                PersonaStarterChooser(library: library) { starterToEdit = $0 }
            }
            .sheet(item: $editingGroup) { PersonaGroupEditor(library: library, group: $0) }
            .alert("Rename persona", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
                TextField("Name", text: $name)
                Button("Save") { if let id = renaming { library.rename(id, name: name) }; renaming = nil }
                Button("Cancel", role: .cancel) { renaming = nil }
            }
            .alert("New persona group", isPresented: $creatingGroup) {
                TextField("Private group name", text: $groupName)
                Button("Create") {
                    do { _ = try library.createGroup(name: groupName, members: library.selectedID.map { [$0] } ?? []) }
                    catch { library.notice = error.localizedDescription }
                }.disabled(groupName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                Button("Cancel", role: .cancel) { }
            } message: { Text("The selected persona is included. Choose members to add others. Group names never appear in floating controls.") }
            .alert("Rename group", isPresented: $renamingGroup) {
                TextField("Private group name", text: $groupName)
                Button("Save") { if let id = library.activeGroupID { library.renameGroup(id, name: groupName) } }
                Button("Cancel", role: .cancel) { }
            }
    }

    @ViewBuilder private func thumbnail(_ persona: SavedPersona, width: CGFloat, height: CGFloat) -> some View {
        if let image = library.renderedImage(for: persona) {
            Image(nsImage: image).resizable().scaledToFit().frame(width: width, height: height)
                .accessibilityLabel(persona.name)
        } else {
            VStack(spacing: 5) {
                Image(systemName: "photo.badge.exclamationmark")
                if width > 100 { Text("Image missing").font(.caption) }
            }.foregroundStyle(.secondary).frame(width: width, height: height)
                .accessibilityLabel("Missing image: " + persona.name)
        }
    }
}

private struct PersonaStarterChooser: View {
    @ObservedObject var library: PersonaLibrary
    let onChoose: (SavedPersona) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var selectedID: String?
    @State private var thumbnails: [String: NSImage] = [:]
    @State private var loading = true
    @State private var importing = false
    @State private var notice: String?
    private let starters = PersonaStarterLibrary()
    private var available: [PersonaStarter] { PersonaStarterLibrary.portraits.filter { thumbnails[$0.id] != nil } }
    private var selected: PersonaStarter? { available.first { $0.id == selectedID } }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Choose a starter portrait").font(.title2.bold())
            Text("Choose one portrait, then edit its role label and background colour.")
                .font(.callout).foregroundStyle(.secondary)
            if loading {
                ProgressView("Opening portraits…").frame(maxWidth: .infinity, minHeight: 280)
            } else if available.isEmpty {
                ContentUnavailableView("Starter portraits unavailable", systemImage: "person.crop.rectangle",
                    description: Text("This build does not include readable starter portraits. Import your own from Add persona."))
                    .frame(height: 280)
            } else {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 4), spacing: 12) {
                    ForEach(available) { portrait in
                        Button { selectedID = portrait.id; notice = nil } label: {
                            VStack(spacing: 8) {
                                if let image = thumbnails[portrait.id] {
                                    Image(nsImage: image).resizable().scaledToFit().frame(height: 128)
                                        .frame(maxWidth: .infinity).accessibilityHidden(true)
                                }
                                Text(portrait.label).font(.caption).lineLimit(2).frame(height: 30)
                            }.padding(8).frame(maxWidth: .infinity)
                                .background(selectedID == portrait.id ? Color.accentColor.opacity(0.12) : Color.primary.opacity(0.035),
                                            in: RoundedRectangle(cornerRadius: 10))
                                .overlay {
                                    RoundedRectangle(cornerRadius: 10).strokeBorder(
                                        selectedID == portrait.id ? Color.accentColor : Color.primary.opacity(0.10),
                                        lineWidth: selectedID == portrait.id ? 2 : 1)
                                }
                                .overlay(alignment: .topTrailing) {
                                    if selectedID == portrait.id {
                                        Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.accentColor)
                                            .padding(6).accessibilityHidden(true)
                                    }
                                }
                        }.buttonStyle(.plain).accessibilityLabel(portrait.label)
                            .accessibilityValue(selectedID == portrait.id ? "Selected" : "")
                    }
                }
                if available.count < PersonaStarterLibrary.portraits.count {
                    Text("Some starter portraits are unavailable in this build.").font(.caption).foregroundStyle(.secondary)
                }
            }
            if let notice { Text(notice).font(.caption).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true) }
            HStack {
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
                Button("Use portrait") {
                    guard let selected, !importing else { return }
                    importing = true
                    do { let persona = try starters.add(selected, to: library); onChoose(persona); dismiss() }
                    catch { notice = error.localizedDescription; importing = false }
                }.keyboardShortcut(.defaultAction).disabled(selected == nil || library.isReadOnly || importing)
            }
        }.padding(24).frame(width: 620).background(Workbench.background).workbenchTheme()
            .task {
                for portrait in PersonaStarterLibrary.portraits {
                    guard !Task.isCancelled else { return }
                    if let image = starters.thumbnail(for: portrait) { thumbnails[portrait.id] = image }
                    await Task.yield()
                }
                loading = false
            }
    }
}

private struct PersonaCardEditor: View {
    @ObservedObject var library: PersonaLibrary
    let persona: SavedPersona
    @Environment(\.dismiss) private var dismiss
    @State private var style: PersonaCardStyle
    init(library: PersonaLibrary, persona: SavedPersona) {
        self.library = library; self.persona = persona; _style = State(initialValue: persona.card ?? PersonaCardStyle())
    }
    private var draft: SavedPersona { var item = persona; item.card = style; return item }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Edit persona card").font(.title2.bold())
            TextField("Visible label", text: $style.label).textFieldStyle(.roundedBorder)
            ColorPicker("Background colour", selection: Binding(get: { Color(nsColor: style.background.nsColor) },
                set: { style.background = InkColor(NSColor($0)) }), supportsOpacity: false)
            if let image = library.renderedImage(for: draft) {
                Image(nsImage: image).resizable().scaledToFit().frame(height: 265).frame(maxWidth: .infinity)
            }
            Text("Leave the label empty to hide it. Scenes keep their existing copy until you use the card again.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            if let notice = library.notice { Text(notice).font(.caption).foregroundStyle(.orange) }
            HStack {
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
                Button("Save card") { if library.updateCard(persona.id, style: style) { dismiss() } }
                    .keyboardShortcut(.defaultAction).disabled(library.isReadOnly || (try? style.validated()) == nil)
            }
        }.padding(24).frame(width: 420).background(Workbench.background).workbenchTheme()
    }
}

private struct PersonaGroupEditor: View {
    @ObservedObject var library: PersonaLibrary
    let group: PersonaGroup
    @Environment(\.dismiss) private var dismiss
    @State private var chosen: Set<UUID>
    init(library: PersonaLibrary, group: PersonaGroup) {
        self.library = library; self.group = group; _chosen = State(initialValue: Set(group.personaIDs))
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Choose group members").font(.title2.bold())
            Text(group.name).font(.headline)
            Text("Preparation only. Floating controls use the members chosen when you show this group.")
                .font(.callout).foregroundStyle(.secondary)
            List(library.items) { item in
                Toggle(item.name, isOn: Binding(get: { chosen.contains(item.id) }, set: { if $0 { chosen.insert(item.id) } else { chosen.remove(item.id) } }))
            }.frame(height: 280)
            if let notice = library.notice { Text(notice).font(.caption).foregroundStyle(.orange) }
            HStack {
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
                Button("Save members") {
                    let ordered = group.personaIDs.filter { chosen.contains($0) } + library.items.map(\.id).filter { chosen.contains($0) && !group.personaIDs.contains($0) }
                    library.setGroupMembers(ordered, in: group.id)
                    if library.groups.first(where: { $0.id == group.id })?.personaIDs == ordered { dismiss() }
                }.keyboardShortcut(.defaultAction).disabled(library.isReadOnly)
            }
        }.padding(24).frame(width: 460).background(Workbench.background).workbenchTheme()
    }
}
