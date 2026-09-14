import SwiftUI
import PhotosUI
import AVFoundation
import ImageIO
import UniformTypeIdentifiers

struct PhotoHandoffView: View {
    @EnvironmentObject private var handoff: PhotoHandoffModel
    @Environment(\.dismiss) private var dismiss
    @State private var selection: PhotosPickerItem?
    @State private var choosingPhoto = false
    @State private var showingCamera = false
    @State private var cameraDenied = false
    @State private var original: Data?
    @State private var preview: UIImage?
    @State private var title = ""
    @State private var notice: String?
    @State private var preparing = false
    @State private var submitting = false
    @State private var discarding = false
    @State private var leaving = false
    @State private var inputTask: Task<Void, Never>?
    @State private var inputID = UUID()
    @FocusState private var editingName: Bool

    private var busy: Bool { preparing || submitting || handoff.isBusy }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                if preview == nil {
                Text("Take or choose a photo.").font(.title2.weight(.semibold))
                Text("Keep it here, or send a copy for your Mac.").foregroundStyle(.secondary)
                HStack(spacing: 12) {
                    Button("Take a photo", systemImage: "camera") { requestCamera() }
                        .buttonStyle(.borderedProminent).accessibilityIdentifier("handoff.camera")
                    Button("Photos", systemImage: "photo.on.rectangle") { choosingPhoto = true }
                        .buttonStyle(.bordered).accessibilityIdentifier("handoff.photos")
                }.controlSize(.large).disabled(busy || original != nil)
                #if DEBUG
                if ProcessInfo.processInfo.arguments.contains("--ui-testing-handoff") {
                    Text("UI test · local only").font(.caption).foregroundStyle(.secondary)
                    Button("Use sample photo") { accept(PhotoHandoffPreview.sampleData()) }
                        .disabled(busy || original != nil).accessibilityIdentifier("handoff.sample")
                }
                #endif
                }
                if cameraDenied {
                    Button("Open Camera Settings", systemImage: "gear") {
                        if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                    }.frame(minHeight: 44)
                }
                if preparing { ProgressView("Opening photo…") }
                if let preview {
                    Image(uiImage: preview).resizable().scaledToFit().frame(maxHeight: 350)
                        .clipShape(RoundedRectangle(cornerRadius: 18)).accessibilityLabel("Selected photo preview")
                    TextField("Name (optional)", text: $title).textFieldStyle(.roundedBorder)
                        .focused($editingName).accessibilityIdentifier("handoff.name").disabled(submitting)
                        .onChange(of: title) { _, value in if value.count > 120 { title = String(value.prefix(120)) } }
                    Text("Your original stays here. Sending shares an optimised JPEG without location metadata.")
                        .font(.footnote).foregroundStyle(.secondary)
                    VStack(spacing: 10) {
                        Button { submit(send: true) } label: {
                            Label("Send photo", systemImage: "icloud.and.arrow.up").frame(maxWidth: .infinity)
                        }.buttonStyle(.borderedProminent).disabled(busy || !handoff.isEnabled)
                            .accessibilityIdentifier("handoff.send")
                        Button { submit(send: false) } label: {
                            Label("Keep on this device", systemImage: "square.and.arrow.down").frame(maxWidth: .infinity)
                        }.buttonStyle(.bordered).disabled(busy).accessibilityIdentifier("handoff.keep")
                    }.controlSize(.large)
                    if !handoff.isEnabled { Text("Enable private iCloud below when you want to send.").font(.footnote).foregroundStyle(.secondary) }
                    Button("Discard preview", role: .destructive) { discarding = true }.disabled(busy).frame(minHeight: 44)
                }
                if let notice { Text(notice).font(.callout).foregroundStyle(.secondary).accessibilityIdentifier("handoff.notice") }
                PhotoHandoffSettingsView()
                    .padding(18).background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20))
                if !handoff.photos.isEmpty {
                    VStack(alignment: .leading, spacing: 14) {
                        Text("Your photo handoff").font(.title3.bold())
                        ForEach(handoff.photos) { photo in
                            NavigationLink { PhotoHandoffDetailView(photoID: photo.id) } label: { PhotoHandoffRow(photo: photo) }
                                .buttonStyle(.plain)
                        }
                    }
                }
            }.padding(20).frame(maxWidth: 720)
        }.frame(maxWidth: .infinity).background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle("Photo for Mac").navigationBarTitleDisplayMode(.inline).toolbar(.hidden, for: .tabBar)
            .navigationBarBackButtonHidden(original != nil || submitting)
            .toolbar {
                if original != nil || submitting {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Back", systemImage: "chevron.left") { leaving = true }.disabled(submitting)
                    }
                }
                ToolbarItemGroup(placement: .keyboard) { Spacer(); Button("Done") { editingName = false } }
            }
            .photosPicker(isPresented: $choosingPhoto, selection: $selection, matching: .images, preferredItemEncoding: .current)
            .onChange(of: selection) { _, value in if let value { load(value) } }
            .fullScreenCover(isPresented: $showingCamera) {
                PhotoHandoffCamera { result in
                    showingCamera = false
                    switch result {
                    case .success(let data): if let data { accept(data) }
                    case .failure(let error): notice = error.localizedDescription
                    }
                }.ignoresSafeArea()
            }
            .confirmationDialog("Discard this photo preview?", isPresented: $discarding, titleVisibility: .visible) {
                Button("Discard preview", role: .destructive) { clearPreview() }
            } message: { Text("This photo has not been kept in Workbench or sent.") }
            .confirmationDialog("Keep this photo before leaving?", isPresented: $leaving, titleVisibility: .visible) {
                Button("Keep on this device") { submit(send: false, leave: true) }
                Button("Discard preview", role: .destructive) { clearPreview(); dismiss() }
                    .accessibilityIdentifier("handoff.discardAndLeave")
            } message: { Text("The preview has not been kept or sent yet.") }
            .onDisappear { inputID = UUID(); inputTask?.cancel() }
    }

    private func requestCamera() {
        notice = nil; cameraDenied = false
        guard UIImagePickerController.isSourceTypeAvailable(.camera) else {
            notice = "Camera is unavailable here. Choose a photo from Photos."; return
        }
        let token = UUID(); inputID = token; preparing = true
        inputTask?.cancel()
        inputTask = Task { @MainActor in
            defer { if inputID == token { preparing = false } }
            let granted: Bool
            switch AVCaptureDevice.authorizationStatus(for: .video) {
            case .authorized: granted = true
            case .notDetermined: granted = await AVCaptureDevice.requestAccess(for: .video)
            default: granted = false
            }
            guard !Task.isCancelled, inputID == token else { return }
            if granted { showingCamera = true }
            else { cameraDenied = true; notice = "Camera access is off. Choose a photo from Photos, or allow Camera in Settings." }
        }
    }

    private func load(_ item: PhotosPickerItem) {
        let token = UUID(); inputID = token; preparing = true; notice = nil
        inputTask?.cancel()
        inputTask = Task { @MainActor in
            defer { if inputID == token { preparing = false; selection = nil } }
            do {
                guard let data = try await item.loadTransferable(type: Data.self) else { throw PhotoHandoffInputError.unreadable }
                guard !Task.isCancelled, inputID == token else { return }
                accept(data)
            } catch { if !Task.isCancelled, inputID == token { notice = error.localizedDescription } }
        }
    }

    private func accept(_ data: Data) {
        do {
            let image = try PhotoHandoffPreview.selected(data)
            original = data; preview = image; notice = nil
        } catch { notice = error.localizedDescription }
    }

    private func clearPreview() { original = nil; preview = nil; title = ""; editingName = false }

    private func submit(send: Bool, leave: Bool = false) {
        guard let original, !busy, !send || handoff.isEnabled else { return }
        submitting = true; editingName = false; notice = nil
        let name = title.trimmingCharacters(in: .whitespacesAndNewlines)
        Task { @MainActor in
            defer { submitting = false }
            guard let id = await handoff.addPhoto(data: original, title: name) else { return }
            clearPreview()
            if send { await handoff.sendPhoto(id) }
            else { notice = "Original kept on this device." }
            if leave { dismiss() }
        }
    }
}

struct PhotoHandoffSettingsView: View {
    @EnvironmentObject private var handoff: PhotoHandoffModel
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Private iCloud", systemImage: "icloud").font(.headline)
            if handoff.isConfigured {
                Text("Use the same Apple Account on iPhone and Mac. Only photos you send are transferred.")
                    .font(.subheadline).foregroundStyle(.secondary)
                Text(handoff.status).font(.subheadline).accessibilityIdentifier("handoff.status")
            }
            if let error = handoff.error {
                Label(error, systemImage: "exclamationmark.circle").font(.callout).foregroundStyle(.secondary)
            }
            if !handoff.isConfigured {
                Text("Private iCloud is unavailable in this build. You can still keep photos here and share a copy.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            HStack {
                if handoff.isEnabled {
                    Button("Refresh", systemImage: "arrow.clockwise") { Task { await handoff.refresh() } }.disabled(handoff.isBusy)
                    Spacer()
                    Button("Turn off") { handoff.disable() }
                } else {
                    Button("Enable private iCloud", systemImage: "icloud") { Task { await handoff.enable() } }
                        .disabled(!handoff.isConfigured || handoff.isBusy).accessibilityIdentifier("handoff.enable")
                }
                if handoff.isBusy { ProgressView().accessibilityLabel("Updating photo handoff") }
            }.frame(minHeight: 44)
            if handoff.isConfigured {
                Text("Open Workbench on Mac to check for arrivals. “In iCloud” confirms upload, not Mac delivery.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
    }
}

struct PhotoHandoffRow: View {
    @EnvironmentObject private var handoff: PhotoHandoffModel
    let photo: HandoffPhoto
    var body: some View {
        HStack(spacing: 14) {
            if let url = handoff.fileURL(for: photo), let image = PhotoHandoffPreview.thumbnail(url) {
                Image(uiImage: image).resizable().scaledToFill().frame(width: 64, height: 64)
                    .clipShape(RoundedRectangle(cornerRadius: 12)).accessibilityHidden(true)
            } else { Image(systemName: "photo").frame(width: 64, height: 64).foregroundStyle(.secondary) }
            VStack(alignment: .leading, spacing: 5) {
                Text(photo.title).font(.headline).lineLimit(2)
                Text(photo.statusLabel).font(.subheadline).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary)
        }.padding(.vertical, 6).accessibilityElement(children: .combine).accessibilityIdentifier("handoff.photoRow")
    }
}

struct PhotoHandoffDetailView: View {
    @EnvironmentObject private var handoff: PhotoHandoffModel
    @Environment(\.dismiss) private var dismiss
    let photoID: UUID
    @State private var removingLocal = false
    @State private var removingCloud = false
    private var photo: HandoffPhoto? { handoff.photos.first { $0.id == photoID } }
    var body: some View {
        ScrollView {
            if let photo {
                VStack(alignment: .leading, spacing: 20) {
                    if let url = handoff.fileURL(for: photo), let image = PhotoHandoffPreview.thumbnail(url, maxPixels: 1400) {
                        Image(uiImage: image).resizable().scaledToFit().frame(maxHeight: 460)
                            .clipShape(RoundedRectangle(cornerRadius: 18)).accessibilityLabel("Photo handoff preview")
                        ShareLink(item: url) { Label("Share a copy", systemImage: "square.and.arrow.up") }
                            .buttonStyle(.bordered).controlSize(.large)
                    }
                    Text(photo.statusLabel).font(.headline).accessibilityIdentifier("handoff.photoStatus")
                    Text("From \(photo.sourceDevice) · \(photo.created.formatted(date: .abbreviated, time: .omitted))")
                        .font(.subheadline).foregroundStyle(.secondary)
                    if !photo.isUploaded {
                        Button("Send photo", systemImage: "icloud.and.arrow.up") { Task { await handoff.sendPhoto(photo.id) } }
                            .buttonStyle(.borderedProminent).controlSize(.large).disabled(!handoff.isEnabled || handoff.isBusy)
                    }
                    PhotoHandoffSettingsView()
                }.padding(20).frame(maxWidth: 720)
            } else { ContentUnavailableView("Photo no longer here", systemImage: "photo") }
        }.frame(maxWidth: .infinity).background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle(photo?.title ?? "Photo handoff").navigationBarTitleDisplayMode(.inline).toolbar(.hidden, for: .tabBar)
            .toolbar {
                if let photo {
                    ToolbarItem(placement: .topBarTrailing) {
                        Menu("Photo options", systemImage: "ellipsis.circle") {
                            if photo.isUploaded {
                                Button("Remove from private iCloud", role: .destructive) { removingCloud = true }.disabled(!handoff.isEnabled || handoff.isBusy)
                            }
                            Button("Remove from this device", role: .destructive) { removingLocal = true }.disabled(handoff.isBusy)
                        }
                    }
                }
            }
            .confirmationDialog("Remove from private iCloud?", isPresented: $removingCloud, titleVisibility: .visible) {
                Button("Remove from private iCloud", role: .destructive) { Task { await handoff.removeFromCloud(photoID) } }
            } message: { Text("Copies already downloaded or used in another project are kept.") }
            .confirmationDialog("Remove from this device?", isPresented: $removingLocal, titleVisibility: .visible) {
                Button("Remove from this device", role: .destructive) {
                    do { try handoff.removeLocalPhoto(photoID); dismiss() } catch { handoff.error = error.localizedDescription }
                }
            } message: { Text("This removes the handoff’s local photos. Share a copy first if needed. Copies in private iCloud and other projects are kept.") }
    }
}

enum PhotoHandoffInputError: LocalizedError {
    case unreadable
    var errorDescription: String? { "Choose a readable still photo under 64 MB and 50 megapixels." }
}

enum PhotoHandoffPreview {
    static func selected(_ data: Data) throws -> UIImage {
        guard !data.isEmpty, data.count <= 64_000_000,
              let source = CGImageSourceCreateWithData(data as CFData, nil), CGImageSourceGetCount(source) == 1,
              let values = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = values[kCGImagePropertyPixelWidth] as? NSNumber, let height = values[kCGImagePropertyPixelHeight] as? NSNumber,
              width.doubleValue > 0, height.doubleValue > 0, width.doubleValue * height.doubleValue <= 50_000_000,
              let image = thumbnail(source, maxPixels: 1400) else { throw PhotoHandoffInputError.unreadable }
        return image
    }
    static func thumbnail(_ url: URL, maxPixels: Int = 240) -> UIImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return thumbnail(source, maxPixels: maxPixels)
    }
    private static func thumbnail(_ source: CGImageSource, maxPixels: Int) -> UIImage? {
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
            kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixels, kCGImageSourceShouldCacheImmediately: true
        ] as CFDictionary) else { return nil }
        return UIImage(cgImage: image)
    }
    #if DEBUG
    static func sampleData() -> Data {
        UIGraphicsImageRenderer(size: CGSize(width: 900, height: 600)).image { context in
            UIColor.systemTeal.setFill(); context.fill(CGRect(x: 0, y: 0, width: 900, height: 600))
            UIColor.white.setFill(); context.fill(CGRect(x: 90, y: 90, width: 720, height: 420))
            UIColor.systemIndigo.setFill(); context.fill(CGRect(x: 140, y: 140, width: 210, height: 120))
        }.jpegData(compressionQuality: 1) ?? Data()
    }
    #endif
}

struct PhotoHandoffCamera: UIViewControllerRepresentable {
    let completion: (Result<Data?, Error>) -> Void
    func makeCoordinator() -> Coordinator { Coordinator(completion: completion) }
    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera; picker.cameraCaptureMode = .photo; picker.mediaTypes = [UTType.image.identifier]
        picker.allowsEditing = false; picker.delegate = context.coordinator
        return picker
    }
    func updateUIViewController(_ controller: UIImagePickerController, context: Context) {}
    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let completion: (Result<Data?, Error>) -> Void
        init(completion: @escaping (Result<Data?, Error>) -> Void) { self.completion = completion }
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { completion(.success(nil)) }
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            do {
                let data: Data
                if let url = info[.imageURL] as? URL {
                    let values = try url.resourceValues(forKeys: [.fileSizeKey])
                    guard let size = values.fileSize, size > 0, size <= 64_000_000 else { throw PhotoHandoffInputError.unreadable }
                    data = try Data(contentsOf: url)
                } else if let image = info[.originalImage] as? UIImage, let encoded = image.jpegData(compressionQuality: 1) { data = encoded }
                else { throw PhotoHandoffInputError.unreadable }
                completion(.success(data))
            } catch { completion(.failure(error)) }
        }
    }
}
