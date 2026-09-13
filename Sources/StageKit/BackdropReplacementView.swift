import AppKit
import SwiftUI

struct BackdropReplacementView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var model: DemoScenes
    @ObservedObject var draft: BackdropReplacement
    @State private var saved: [BackdropChoice] = []
    @State private var starters: [BackdropChoice] = []
    @State private var loading = true
    private var current: DemoScene? { model.scenes.first { $0.id == draft.sceneID } }
    private var stale: Bool { current.map { SceneBackdrop($0) != draft.original } ?? true }
    private var aspect: CGFloat {
        let size = model.outputSize
        return size.width / max(1, size.height)
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Change backdrop").font(.title2.weight(.semibold))
                    Text(current?.name ?? "Scene unavailable").foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer()
                Button("Cancel") { draft.cancel(); dismiss() }.keyboardShortcut(.cancelAction)
            }
            HStack(alignment: .top, spacing: 20) {
                VStack(alignment: .leading, spacing: 12) {
                    GeometryReader { space in
                        let width = min(space.size.width, space.size.height * aspect)
                        let height = width / aspect
                        Group {
                            if let candidate = draft.candidate, let current {
                                BackdropScenePreview(scene: draft.previewScene(current: current), image: candidate.image.image,
                                    logo: model.logoImage(for: current), hand: model.handImage(for: current), persona: model.personaImage(for: current))
                            } else {
                                ContentUnavailableView("Choose a backdrop", systemImage: "photo",
                                    description: Text("Your scene’s layout will stay in place."))
                            }
                        }.frame(width: width, height: height)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.primary.opacity(0.12)))
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }.frame(height: 260)
                        .accessibilityLabel("Replacement scene preview")
                    if let candidate = draft.candidate {
                        Text(candidate.name).font(.callout.weight(.medium)).lineLimit(1)
                        Text(candidate.source + " · Preview only").font(.caption).foregroundStyle(.secondary)
                    }
                    VStack(spacing: 10) {
                        cropSlider("Horizontal crop", value: $draft.x, range: 0...1, low: "Left", high: "Right")
                        cropSlider("Vertical crop", value: $draft.y, range: 0...1, low: "Bottom", high: "Top")
                        HStack {
                            Text("Zoom").frame(width: 98, alignment: .leading)
                            Slider(value: $draft.zoom, in: 1...3).accessibilityLabel("Backdrop zoom")
                            Text("\(draft.zoom, specifier: "%.1f")×").monospacedDigit().frame(width: 34)
                        }
                        HStack {
                            Button("Centre crop") { draft.centreCrop() }
                            Spacer()
                            Text("Only the backdrop changes").foregroundStyle(.secondary)
                        }
                    }.font(.caption).disabled(draft.candidate == nil || draft.choosingFile)
                }.frame(maxWidth: .infinity)
                VStack(alignment: .leading, spacing: 10) {
                    Button { draft.chooseFile() } label: { Label("Choose image…", systemImage: "folder") }
                        .disabled(draft.choosingFile)
                    ScrollView {
                        VStack(alignment: .leading, spacing: 9) {
                            if loading { ProgressView().controlSize(.small) }
                            if !saved.isEmpty {
                                Text("From saved scenes").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                                ForEach(saved) { choice in choiceButton(choice) }
                            }
                            if !starters.isEmpty {
                                Text("Bundled starters").font(.caption.weight(.semibold)).foregroundStyle(.secondary).padding(.top, 4)
                                ForEach(starters) { choice in choiceButton(choice) }
                            }
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    }
                }.frame(width: 205, height: 445)
            }
            Group {
                if let message = draft.notice ?? (stale ? BackdropReplacementError.staleScene.localizedDescription : nil) {
                    Label(message, systemImage: "info.circle").font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                } else { Color.clear }
            }.frame(height: 32, alignment: .topLeading)
            Divider()
            HStack {
                Text("Your saved scene stays unchanged until you use this backdrop.")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Use backdrop") {
                    do { try model.applyBackdrop(draft); dismiss() }
                    catch { draft.notice = error.localizedDescription }
                }.buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
                    .disabled(!draft.canApply || stale || model.storageBlocked)
            }
        }.padding(20).frame(width: 840, height: 660)
            .background(Workbench.background).tint(Workbench.accent).workbenchTheme()
            .task {
                guard let current else { loading = false; return }
                let scenes = model.scenes, root = model.root, available = model.starters
                let work = Task.detached(priority: .userInitiated) {
                    (BackdropChoices.saved(scenes: scenes, root: root, preferred: current, isCancelled: { Task.isCancelled }),
                     BackdropChoices.starters(available, isCancelled: { Task.isCancelled }))
                }
                let values = await withTaskCancellationHandler(operation: { await work.value }, onCancel: { work.cancel() })
                guard !Task.isCancelled, draft.active else { return }
                saved = values.0; starters = values.1; loading = false
            }
            .onDisappear { draft.cancel() }
    }
    private func cropSlider(_ title: String, value: Binding<Double>, range: ClosedRange<Double>, low: String, high: String) -> some View {
        HStack {
            Text(title).frame(width: 98, alignment: .leading)
            Text(low).foregroundStyle(.secondary)
            Slider(value: value, in: range).accessibilityLabel(title)
            Text(high).foregroundStyle(.secondary)
        }
    }
    private func choiceButton(_ choice: BackdropChoice) -> some View {
        let selected = draft.candidate?.selectionID == choice.id
        return Button {
            do { try draft.choose(choice) }
            catch { draft.notice = error.localizedDescription + " The previous preview is unchanged." }
        } label: {
            HStack(spacing: 8) {
                Image(nsImage: choice.thumbnail).resizable().aspectRatio(contentMode: .fill)
                    .frame(width: 64, height: 44).clipped().clipShape(RoundedRectangle(cornerRadius: 5))
                VStack(alignment: .leading, spacing: 2) {
                    Text(choice.name).font(.caption.weight(.medium)).lineLimit(2)
                    Text(choice.caption).font(.system(size: 10)).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                if selected { Image(systemName: "checkmark.circle.fill").foregroundStyle(Workbench.accent) }
            }.padding(6).frame(maxWidth: .infinity, alignment: .leading)
                .background(selected ? Workbench.accent.opacity(0.1) : Workbench.surface, in: RoundedRectangle(cornerRadius: 7))
                .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(selected ? Workbench.accent : .clear))
        }.buttonStyle(.plain).disabled(draft.choosingFile)
            .accessibilityLabel(choice.name + ", " + choice.caption + (selected ? ", selected" : ""))
            .accessibilityAddTraits(selected ? [.isSelected] : [])
    }
}

/// The preview has no capture layer, editing handles or desktop side effects.
struct BackdropScenePreview: NSViewRepresentable {
    let scene: DemoScene
    let image: NSImage
    let logo: NSImage?
    let hand: NSImage?
    let persona: NSImage?
    func makeNSView(context: Context) -> BackdropScenePreviewView { BackdropScenePreviewView() }
    func updateNSView(_ view: BackdropScenePreviewView, context: Context) {
        view.scene = scene; view.image = image; view.logo = logo; view.hand = hand; view.persona = persona; view.needsDisplay = true
    }
}

final class BackdropScenePreviewView: NSView {
    var scene: DemoScene?
    var image: NSImage?
    var logo: NSImage?
    var hand: NSImage?
    var persona: NSImage?
    override func draw(_ dirtyRect: NSRect) {
        guard let scene, let image else { return }
        SceneRenderer.draw(scene, image: image, size: bounds.size, logoImage: logo, handImage: hand, personaImage: persona)
    }
}
