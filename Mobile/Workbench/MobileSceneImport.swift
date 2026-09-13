import Foundation
import ImageIO
#if canImport(SceneSyncKit)
import SceneSyncKit
#endif

/// An explicit copy into Scenes, with a portable recovery attachment for the
/// earlier mobile editor. The attachment is never flattened into its background.
@MainActor enum MobileSceneImport {
    struct Attachment: Codable, Equatable {
        var format = "workbench-mobile-scene"
        var version = 1
        var project: MobileImageProject
        /// Original local names are identifiers only, never external file paths.
        var assetMap: [String: String]
    }

    static func convert(project: MobileImageProject, store: MobileStore,
                        scenes: SceneLibraryModel) throws -> SavedSceneRecord {
        guard !store.writesDisabled, !scenes.isStorageBlocked else { throw SceneDocumentError.storageBlocked }
        try validate(project)
        let originalAssets = try readAssets(project.allAssets, directory: store.disk.directory,
                                           assetsDirectory: store.disk.assets) { store.disk.assetURL($0) }
        let map = originalAssets.mapValues(SceneAsset.name)
        let attachment = Attachment(project: project, assetMap: map)
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        let attachmentBytes = try encoder.encode(attachment)
        guard attachmentBytes.count <= 8_000_000 else { throw unsupportedAttachment() }

        let title = project.title.trimmingCharacters(in: .whitespacesAndNewlines)
        var scene = PortableScene(name: title.isEmpty ? "Imported scene" : String(title.prefix(160)),
                                  background: try mapped(project.asset, in: map))
        scene.zoom = min(3, project.zoom)
        let size = try imageSize(required(originalAssets[project.asset]))
        // The earlier editor stores a top-left image centre. Scenes store travel
        // across the overflowing image in an unflipped, landscape canvas.
        let scale = max(16 / size.width, 9 / size.height) * scene.zoom
        scene.backgroundX = travel(centre: project.centerX, fitted: size.width * scale, canvas: 16)
        scene.backgroundY = 1 - travel(centre: project.centerY, fitted: size.height * scale, canvas: 9)
        if let logo = project.logoAsset {
            scene.logo = SceneLogoLayer(image: try mapped(logo, in: map), corner: "topLeft", width: 0.22, backing: "none")
        }
        if let persona = project.personaAsset {
            scene.persona = ScenePersonaLayer(image: try mapped(persona, in: map), x: 0.95, y: 0.07, width: 0.20)
        }
        scene.legacyMobileProject = attachmentBytes
        scene.retainedAssets = Array(Set(map.values)).sorted()
        var portableAssets: [String: Data] = [:]
        for (name, bytes) in originalAssets { portableAssets[try mapped(name, in: map)] = bytes }
        // Complete validation precedes every durable copy or scene insertion.
        _ = try ScenePackage(scene: scene, assets: portableAssets).validated()
        for name in portableAssets.keys.sorted() { _ = try scenes.importAsset(try required(portableAssets[name])) }
        return try scenes.create(scene)
    }

    /// Decode only. Unknown attachment or project fields are rejected so a newer
    /// editor's work cannot be silently lost by this recovery path.
    static func decode(_ scene: PortableScene) throws -> Attachment {
        _ = try scene.validated()
        guard let bytes = scene.legacyMobileProject, !bytes.isEmpty, bytes.count <= 8_000_000,
              let object = try JSONSerialization.jsonObject(with: bytes) as? [String: Any],
              Set(object.keys) == ["format", "version", "project", "assetMap"],
              let projectObject = object["project"] as? [String: Any],
              Set(projectObject.keys).isSubset(of: projectKeys) else { throw unsupportedAttachment() }
        let attachment = try JSONDecoder().decode(Attachment.self, from: bytes)
        guard attachment.format == "workbench-mobile-scene", attachment.version == 1 else { throw unsupportedAttachment() }
        try validate(attachment.project)
        guard Set(attachment.assetMap.keys) == attachment.project.allAssets,
              attachment.assetMap.values.allSatisfy(SceneAsset.isName),
              Set(attachment.assetMap.values).isSubset(of: Set(scene.retainedAssets ?? [])) else { throw unsupportedAttachment() }
        return attachment
    }

    /// Recover a separately saved mobile project, with new local asset names and
    /// a new project ID. The scene and any original mobile project remain intact.
    static func recover(scene: PortableScene, store: MobileStore,
                        scenes: SceneLibraryModel) throws -> MobileImageProject {
        guard !store.writesDisabled else { throw SceneDocumentError.storageBlocked }
        let attachment = try decode(scene)
        let hashes = Set(attachment.assetMap.values)
        let bytes = try readAssets(hashes, directory: scenes.directory,
                                   assetsDirectory: scenes.directory.appendingPathComponent("Assets", isDirectory: true)) {
            try scenes.assetURL($0)
        }
        for (name, data) in bytes { try SceneAsset.validate(data, named: name) }
        try checkDirectory(store.disk.directory); try checkDirectory(store.disk.assets)
        var imported: [String: String] = [:]
        do {
            for hash in hashes.sorted() { imported[hash] = try store.disk.importAsset(try required(bytes[hash]), suffix: "image") }
            var recovered = attachment.project
            recovered.id = UUID()
            func local(_ original: String) throws -> String { try mapped(mapped(original, in: attachment.assetMap), in: imported) }
            recovered.asset = try local(recovered.asset)
            recovered.foregroundAsset = try recovered.foregroundAsset.map(local)
            recovered.logoAsset = try recovered.logoAsset.map(local)
            recovered.personaAsset = try recovered.personaAsset.map(local)
            try validate(recovered)
            guard store.change({ $0.images.insert(recovered, at: 0) }) else {
                throw MobileStoreError.invalid(store.error ?? "The recovered project could not be saved. Its scene is unchanged.")
            }
            return recovered
        } catch {
            // These fresh UUID files have never belonged to an earlier project.
            for name in imported.values { if let url = store.disk.assetURL(name) { try? FileManager.default.removeItem(at: url) } }
            throw error
        }
    }

    private static let projectKeys: Set<String> = ["id", "title", "kind", "asset", "modified", "zoom", "centerX", "centerY",
        "wallpaperAspect", "drawing", "foregroundAsset", "logoAsset", "personaAsset", "caption"]

    private static func validate(_ project: MobileImageProject) throws {
        var document = MobileDocument(); document.images = [project]; _ = try document.validated()
        guard project.modified.timeIntervalSince1970.isFinite else { throw unsupportedAttachment() }
    }

    private static func unsupportedAttachment() -> MobileStoreError {
        .invalid("This mobile original needs a compatible Workbench version or its retained pictures. The scene and original files have been kept.")
    }

    private static func mapped(_ name: String, in map: [String: String]) throws -> String {
        guard let result = map[name] else { throw unsupportedAttachment() }; return result
    }
    private static func required<T>(_ value: T?) throws -> T {
        guard let value else { throw SceneDocumentError.missingAsset }; return value
    }

    private static func readAssets(_ names: Set<String>, directory: URL, assetsDirectory: URL,
                                   url: (String) throws -> URL?) throws -> [String: Data] {
        try checkDirectory(directory); try checkDirectory(assetsDirectory)
        var locations: [String: URL] = [:], total = 0
        for name in names.sorted() {
            guard let location = try url(name) else { throw SceneDocumentError.missingAsset }
            let attributes = try FileManager.default.attributesOfItem(atPath: location.path)
            guard attributes[.type] as? FileAttributeType == .typeRegular,
                  let size = attributes[.size] as? NSNumber, size.intValue > 0,
                  size.intValue <= SceneAsset.maximumBytes else { throw SceneDocumentError.missingAsset }
            total += size.intValue
            guard total <= 90_000_000 else { throw SceneDocumentError.invalid("These original pictures are too large to transfer together. They have been kept on this device.") }
            locations[name] = location
        }
        var result: [String: Data] = [:], actualTotal = 0
        for (name, location) in locations {
            let handle = try FileHandle(forReadingFrom: location)
            defer { try? handle.close() }
            let data = try handle.read(upToCount: SceneAsset.maximumBytes + 1) ?? Data()
            try SceneAsset.validate(data, named: SceneAsset.name(for: data))
            actualTotal += data.count
            guard actualTotal <= 90_000_000 else { throw SceneDocumentError.missingAsset }
            result[name] = data
        }
        return result
    }

    private static func checkDirectory(_ url: URL) throws {
        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
            guard attributes[.type] as? FileAttributeType == .typeDirectory else { throw SceneDocumentError.storageBlocked }
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            // Absent destination directories may be created by the owned store.
        }
    }

    private static func imageSize(_ data: Data) throws -> (width: Double, height: Double) {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Double,
              let height = properties[kCGImagePropertyPixelHeight] as? Double else { throw SceneDocumentError.missingAsset }
        let orientation = properties[kCGImagePropertyOrientation] as? Int ?? 1
        return (5...8).contains(orientation) ? (height, width) : (width, height)
    }

    private static func travel(centre: Double, fitted: Double, canvas: Double) -> Double {
        guard fitted - canvas > 0.000001 else { return 0.5 }
        return min(1, max(0, (fitted * centre - canvas / 2) / (fitted - canvas)))
    }
}
