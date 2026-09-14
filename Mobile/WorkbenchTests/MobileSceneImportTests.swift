import XCTest
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import PencilKit
@testable import WorkbenchMobile
#if canImport(SceneSyncKit)
import SceneSyncKit
#endif

@MainActor final class MobileSceneImportTests: XCTestCase {
    private func directory() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("MobileSceneImportTests-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        return root
    }

    private func image(_ seed: Int = 10, width: Int = 4, height: Int = 3) throws -> Data {
        let context = try XCTUnwrap(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(red: CGFloat(seed) / 255, green: 0.3, blue: 0.7, alpha: 0.8))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.setFillColor(CGColor(gray: 1, alpha: 1)); context.fill(CGRect(x: 0, y: 0, width: 1, height: 1))
        let result = NSMutableData()
        let destination = try XCTUnwrap(CGImageDestinationCreateWithData(result, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, try XCTUnwrap(context.makeImage()), nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        return result as Data
    }

    private func fixture(kind: MobileImageKind = .backdrop) throws -> (MobileStore, MobileImageProject, [String: Data]) {
        let store = MobileStore(directory: try directory())
        var sources: [String: Data] = [:]
        func asset(_ seed: Int) throws -> String {
            let data = try image(seed), name = try store.disk.importAsset(data, suffix: "image")
            sources[name] = data; return name
        }
        var project = MobileImageProject(title: "Synthetic original collage", kind: kind, asset: try asset(10))
        project.modified = Date(timeIntervalSince1970: 1234)
        project.zoom = 2; project.centerX = 0.6; project.centerY = 0.3; project.wallpaperAspect = 0.72
        project.foregroundAsset = try asset(50); project.logoAsset = try asset(100); project.personaAsset = try asset(200)
        project.caption = "Synthetic original caption\nSecond line"
        project.drawing = PKDrawing().dataRepresentation()
        XCTAssertTrue(store.change { $0.images = [project] })
        return (store, project, sources)
    }

    func testCrossDeviceRoundTripKeepsOriginalBytesAndEveryEditableField() async throws {
        let (source, project, originalAssets) = try fixture()
        let originalManifest = try Data(contentsOf: source.disk.manifest)
        let scenes = SceneLibraryModel(directory: try directory())
        let record = try MobileSceneImport.convert(project: project, store: source, scenes: scenes)
        XCTAssertNotEqual(record.id, project.id)
        XCTAssertEqual(source.document.images, [project])
        XCTAssertEqual(try Data(contentsOf: source.disk.manifest), originalManifest)
        let attachment = try MobileSceneImport.decode(record.scene)
        XCTAssertEqual(attachment.project, project)
        XCTAssertEqual(Set(attachment.assetMap.keys), project.allAssets)
        XCTAssertEqual(record.scene.assets.count, 4)
        XCTAssertEqual(Set(record.scene.retainedAssets ?? []), Set(attachment.assetMap.values))
        XCTAssertEqual(record.scene.logo?.image, attachment.assetMap[try XCTUnwrap(project.logoAsset)])
        XCTAssertEqual(record.scene.logo?.corner, "topLeft")
        XCTAssertEqual(record.scene.persona?.image, attachment.assetMap[try XCTUnwrap(project.personaAsset)])
        XCTAssertEqual(record.scene.backgroundX, 0.7, accuracy: 0.000001)
        XCTAssertEqual(record.scene.backgroundY, 0.82, accuracy: 0.000001)

        let package = try scenes.package(for: record.scene), exported = try package.encoded()
        for (oldName, original) in originalAssets {
            XCTAssertEqual(package.assets[try XCTUnwrap(attachment.assetMap[oldName])], original)
            XCTAssertEqual(try Data(contentsOf: XCTUnwrap(source.disk.assetURL(oldName))), original)
        }
        XCTAssertNil(exported.range(of: Data(source.disk.directory.path.utf8)))
        let receiverScenes = SceneLibraryModel(directory: try directory())
        let received = try receiverScenes.importPackage(exported)
        let receiverMobile = MobileStore(directory: try directory())
        let recovered = try MobileSceneImport.recover(scene: received.scene, store: receiverMobile, scenes: receiverScenes)
        XCTAssertNotEqual(recovered.id, project.id)
        XCTAssertEqual(receiverMobile.document.images, [recovered])
        XCTAssertEqual(try receiverMobile.disk.load().images, [recovered])
        let pairs = [(project.asset, recovered.asset),
                     (try XCTUnwrap(project.foregroundAsset), try XCTUnwrap(recovered.foregroundAsset)),
                     (try XCTUnwrap(project.logoAsset), try XCTUnwrap(recovered.logoAsset)),
                     (try XCTUnwrap(project.personaAsset), try XCTUnwrap(recovered.personaAsset))]
        for (oldName, newName) in pairs {
            XCTAssertNotEqual(oldName, newName)
            XCTAssertEqual(try Data(contentsOf: XCTUnwrap(receiverMobile.disk.assetURL(newName))), originalAssets[oldName])
        }
        var expected = project
        expected.id = recovered.id; expected.asset = recovered.asset; expected.foregroundAsset = recovered.foregroundAsset
        expected.logoAsset = recovered.logoAsset; expected.personaAsset = recovered.personaAsset
        XCTAssertEqual(recovered, expected, "Drawing, caption, kind, aspect, crop and date must survive without flattening")
        XCTAssertEqual(try Data(contentsOf: source.disk.manifest), originalManifest)
        XCTAssertEqual(try MobileSceneImport.decode(received.scene), attachment)
    }

    func testExplicitConversionAlwaysCreatesSeparateScenesAndWallpaperRemainsIndependent() async throws {
        let (store, initial, _) = try fixture(kind: .wallpaper)
        var project = initial; project.zoom = 4.5
        XCTAssertTrue(store.change { $0.images = [project] })
        let before = try Data(contentsOf: store.disk.manifest)
        let scenes = SceneLibraryModel(directory: try directory())
        let first = try MobileSceneImport.convert(project: project, store: store, scenes: scenes)
        let second = try MobileSceneImport.convert(project: project, store: store, scenes: scenes)
        XCTAssertNotEqual(first.id, second.id); XCTAssertEqual(scenes.records.count, 2)
        XCTAssertEqual(first.scene.zoom, 3)
        XCTAssertEqual(try MobileSceneImport.decode(first.scene).project.zoom, 4.5)
        var edited = first.scene; edited.name = "Independent Mac scene"; edited.zoom = 1
        _ = try scenes.save(edited, expectedRevision: first.revision)
        XCTAssertEqual(store.document.images, [project])
        XCTAssertEqual(try Data(contentsOf: store.disk.manifest), before)
        let recovered = try MobileSceneImport.recover(scene: edited, store: store, scenes: scenes)
        XCTAssertEqual(recovered.kind, .wallpaper); XCTAssertEqual(recovered.wallpaperAspect, 0.72)
        XCTAssertEqual(recovered.zoom, 4.5); XCTAssertEqual(recovered.centerY, 0.3)
        XCTAssertEqual(store.document.images.first { $0.id == project.id }, project)
    }

    func testMissingMalformedOversizedOrLinkedSourcesDoNotCommitOrChangeOriginalManifest() async throws {
        for failure in ["missing", "malformed", "oversized", "linked", "linked-directory"] {
            let (store, project, _) = try fixture()
            let before = try Data(contentsOf: store.disk.manifest)
            let asset = try XCTUnwrap(store.disk.assetURL(project.asset))
            switch failure {
            case "missing": try FileManager.default.removeItem(at: asset)
            case "malformed": try Data("Not an image".utf8).write(to: asset)
            case "oversized":
                let file = try FileHandle(forWritingTo: asset)
                try file.truncate(atOffset: UInt64(SceneAsset.maximumBytes + 1)); try file.close()
            case "linked":
                let outside = try directory().appendingPathComponent("external.image")
                try image().write(to: outside); try FileManager.default.removeItem(at: asset)
                try FileManager.default.createSymbolicLink(at: asset, withDestinationURL: outside)
            default:
                let outside = try directory().appendingPathComponent("OriginalAssets")
                try FileManager.default.moveItem(at: store.disk.assets, to: outside)
                try FileManager.default.createSymbolicLink(at: store.disk.assets, withDestinationURL: outside)
            }
            let destination = try directory(), scenes = SceneLibraryModel(directory: destination)
            XCTAssertThrowsError(try MobileSceneImport.convert(project: project, store: store, scenes: scenes), failure)
            XCTAssertEqual(try Data(contentsOf: store.disk.manifest), before)
            XCTAssertEqual(store.document.images, [project]); XCTAssertTrue(scenes.records.isEmpty)
            XCTAssertFalse(FileManager.default.fileExists(atPath: destination.appendingPathComponent("scene-library.json").path))
            XCTAssertFalse(FileManager.default.fileExists(atPath: destination.appendingPathComponent("Assets").path))
        }
    }

    func testUnknownNewerMalformedAndUnretainedAttachmentsRejectBeforeRecoveryWrites() async throws {
        let (store, project, _) = try fixture(kind: .markup)
        let scenes = SceneLibraryModel(directory: try directory())
        let record = try MobileSceneImport.convert(project: project, store: store, scenes: scenes)
        let original = try XCTUnwrap(record.scene.legacyMobileProject)
        for mutation in ["version", "format", "attachment-field", "project-field", "map", "unretained", "malformed"] {
            var scene = record.scene
            var object = try XCTUnwrap(JSONSerialization.jsonObject(with: original) as? [String: Any])
            switch mutation {
            case "version": object["version"] = 999
            case "format": object["format"] = "a-newer-editor"
            case "attachment-field": object["newerImportantField"] = "Keep original bytes"
            case "project-field":
                var value = try XCTUnwrap(object["project"] as? [String: Any]); value["newerEditableLayer"] = ["content": "Preserve"]
                object["project"] = value
            case "map": object["assetMap"] = ["../../outside.png": SceneAsset.name(for: try image())]
            case "unretained": scene.retainedAssets = []
            default: break
            }
            scene.legacyMobileProject = mutation == "malformed" ? Data("Unfinished attachment".utf8) : try JSONSerialization.data(withJSONObject: object)
            let unchanged = scene, destination = MobileStore(directory: try directory())
            XCTAssertThrowsError(try MobileSceneImport.recover(scene: scene, store: destination, scenes: scenes), mutation)
            XCTAssertEqual(scene, unchanged)
            XCTAssertFalse(FileManager.default.fileExists(atPath: destination.disk.manifest.path))
            XCTAssertFalse(FileManager.default.fileExists(atPath: destination.disk.assets.path))
        }
        XCTAssertEqual(scenes.records[0].scene.legacyMobileProject, original)
    }

    func testMissingRetainedPictureDoesNotPartiallyRecoverOrChangeSourceScene() async throws {
        let (store, project, _) = try fixture()
        let scenes = SceneLibraryModel(directory: try directory())
        let record = try MobileSceneImport.convert(project: project, store: store, scenes: scenes)
        let attachment = try MobileSceneImport.decode(record.scene)
        let foreground = try XCTUnwrap(attachment.assetMap[try XCTUnwrap(project.foregroundAsset)])
        let manifest = scenes.directory.appendingPathComponent("scene-library.json"), before = try Data(contentsOf: manifest)
        try FileManager.default.removeItem(at: scenes.assetURL(foreground))
        let destination = MobileStore(directory: try directory())
        XCTAssertThrowsError(try MobileSceneImport.recover(scene: record.scene, store: destination, scenes: scenes))
        XCTAssertTrue(destination.document.images.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: destination.disk.assets.path))
        XCTAssertEqual(try Data(contentsOf: manifest), before)
    }

    func testReplacingVisibleScenePicturesKeepsTheEditableOriginalRecoverable() async throws {
        let (source, project, originalAssets) = try fixture()
        let scenes = SceneLibraryModel(directory: try directory())
        let record = try MobileSceneImport.convert(project: project, store: source, scenes: scenes)
        var edited = record.scene
        edited.background = try scenes.importAsset(image(30))
        edited.logo?.image = try scenes.importAsset(image(80))
        edited.persona?.image = try scenes.importAsset(image(180))
        XCTAssertEqual(edited.assets.count, 7, "Current artwork and retained originals have independent ownership")
        let saved = try scenes.save(edited, expectedRevision: record.revision)
        let destination = MobileStore(directory: try directory())
        let recovered = try MobileSceneImport.recover(scene: saved.scene, store: destination, scenes: scenes)
        XCTAssertEqual(try Data(contentsOf: XCTUnwrap(destination.disk.assetURL(recovered.asset))), originalAssets[project.asset])
        XCTAssertEqual(try Data(contentsOf: XCTUnwrap(destination.disk.assetURL(try XCTUnwrap(recovered.logoAsset)))), originalAssets[try XCTUnwrap(project.logoAsset)])
        XCTAssertEqual(try MobileSceneImport.decode(saved.scene).project, project)
    }

    func testFailedRecoveryCommitKeepsExistingLibraryAndRemovesOnlyItsFreshCopies() async throws {
        let (source, project, _) = try fixture()
        let scenes = SceneLibraryModel(directory: try directory())
        let record = try MobileSceneImport.convert(project: project, store: source, scenes: scenes)
        let destination = MobileStore(directory: try directory())
        let kept = try destination.disk.importAsset(image(), suffix: "image")
        XCTAssertTrue(destination.change { document in
            document.images = (0..<500).map { MobileImageProject(title: "Existing \($0)", kind: .markup, asset: kept) }
        })
        let before = try Data(contentsOf: destination.disk.manifest)
        XCTAssertThrowsError(try MobileSceneImport.recover(scene: record.scene, store: destination, scenes: scenes))
        XCTAssertEqual(try Data(contentsOf: destination.disk.manifest), before)
        XCTAssertEqual(destination.document.images.count, 500)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: destination.disk.assets.path), [kept])
        XCTAssertEqual(try Data(contentsOf: XCTUnwrap(destination.disk.assetURL(kept))), try image())
    }
}
