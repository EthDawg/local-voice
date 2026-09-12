import SwiftUI

struct PersonaLibraryView: View {
    @ObservedObject var library: PersonaLibrary
    var onChoose: ((SavedPersona) -> Void)? = nil
    @Environment(\.dismiss) private var dismiss
    @State private var renaming: UUID?
    @State private var name = ""
    @State private var showAfterDismiss = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Personas").font(.title2.bold())
                Spacer()
                Button("Import image…") { library.importImage() }.disabled(library.isReadOnly)
                Button("Paste image") { library.pasteImage() }.disabled(library.isReadOnly)
                Button("Done") { dismiss() }.keyboardShortcut(.cancelAction)
            }
            Text("Bring a finished persona card. Its artwork and transparency stay as imported.")
                .font(.callout).foregroundStyle(.secondary)
            HStack(alignment: .top, spacing: 20) {
                List(selection: $library.selectedID) {
                    ForEach(library.items) { persona in
                        HStack(spacing: 10) {
                            thumbnail(persona, width: 52, height: 54)
                            Text(persona.name).lineLimit(2)
                        }.padding(.vertical, 4).tag(persona.id)
                            .contextMenu {
                                Button("Rename…") { renaming = persona.id; name = persona.name }.disabled(library.isReadOnly)
                                Button("Remove from saved personas") { library.remove(persona.id) }.disabled(library.isReadOnly)
                            }
                    }
                }.frame(width: 235, height: 285).overlay {
                    if library.items.isEmpty {
                        Text("Your saved personas\nappear here.").multilineTextAlignment(.center)
                            .foregroundStyle(.secondary).padding()
                    }
                }
                VStack(alignment: .leading, spacing: 12) {
                    if let selected = library.selected {
                        thumbnail(selected, width: 265, height: 155)
                            .frame(maxWidth: .infinity)
                        Text(selected.name).font(.headline).lineLimit(2)
                        HStack {
                            Button(library.overlayVisible ? "Hide floating persona" : "Show over browser") {
                                if library.overlayVisible { library.hideOverlay() }
                                else { showAfterDismiss = true; dismiss() }
                            }.disabled(library.image(named: selected.image) == nil)
                            if let onChoose {
                                Button("Use in scene") { onChoose(selected); dismiss() }
                                    .disabled(library.image(named: selected.image) == nil)
                            }
                        }
                        Toggle("Lock position · clicks pass through", isOn: Binding(
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
                    } else {
                        Image(systemName: "person.crop.rectangle.stack").font(.system(size: 38)).foregroundStyle(.secondary)
                        Text("Choose or import a persona").font(.headline)
                        Text("Use the same saved image over your browser or inside a mobile scene.")
                            .font(.callout).foregroundStyle(.secondary)
                    }
                }.frame(width: 285, alignment: .leading)
            }
            if let notice = library.notice {
                Text(notice).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Text("Share your whole screen to include the floating persona. Add it to a scene when sharing that window.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }.padding(24).frame(width: 590).background(Workbench.background).workbenchTheme()
            .onDisappear {
                guard showAfterDismiss else { return }
                showAfterDismiss = false
                library.showOverlay()
            }
            .alert("Rename persona", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
                TextField("Name", text: $name)
                Button("Save") { if let id = renaming { library.rename(id, name: name) }; renaming = nil }
                Button("Cancel", role: .cancel) { renaming = nil }
            }
    }

    @ViewBuilder private func thumbnail(_ persona: SavedPersona, width: CGFloat, height: CGFloat) -> some View {
        if let image = library.image(named: persona.image) {
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
