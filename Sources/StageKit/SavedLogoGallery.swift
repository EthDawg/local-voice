import SwiftUI

struct SavedLogoGallery: View {
    @ObservedObject var model: DemoScenes
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var renaming: UUID?
    @State private var name = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack { Text("Saved logos").font(.title2.bold()); Spacer(); Button("Done") { dismiss() } }
            TextField("Find a customer logo", text: $query).textFieldStyle(.roundedBorder)
            List {
                ForEach(model.savedLogos.filter { query.isEmpty || $0.name.localizedCaseInsensitiveContains(query) }) { logo in
                    HStack(spacing: 12) {
                        if let image = NSImage(contentsOf: model.root.appendingPathComponent(logo.image)) {
                            Image(nsImage: image).resizable().scaledToFit().frame(width: 70, height: 35).padding(6)
                                .background {
                                    Canvas { context, size in
                                        for row in 0...Int(size.height / 8) {
                                            for column in 0...Int(size.width / 8) {
                                                let rect = CGRect(x: column * 8, y: row * 8, width: 8, height: 8)
                                                context.fill(Path(rect), with: .color(Color(white: (row + column).isMultiple(of: 2) ? 0.55 : 0.7)))
                                            }
                                        }
                                    }
                                }.clipShape(RoundedRectangle(cornerRadius: 5))
                        }
                        Text(logo.name).lineLimit(2)
                        Spacer()
                        Button("Use") { model.useSavedLogo(logo); dismiss() }
                        Menu {
                            Button("Rename") { renaming = logo.id; name = logo.name }
                            Button("Remove from saved logos") { model.removeSavedLogo(logo.id) }
                        } label: { Image(systemName: "ellipsis") }.menuStyle(.borderlessButton).fixedSize()
                    }.padding(.vertical, 5).accessibilityElement(children: .contain)
                }
            }
            Text("Removing a saved logo keeps every customer scene that already uses it.").font(.caption).foregroundStyle(.secondary)
        }.padding(24).frame(width: 560, height: 430).background(Workbench.background).workbenchTheme()
            .alert("Rename saved logo", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
                TextField("Name", text: $name)
                Button("Save") { if let id = renaming { model.renameSavedLogo(id, name: name) }; renaming = nil }
                Button("Cancel", role: .cancel) { renaming = nil }
            }
    }
}
