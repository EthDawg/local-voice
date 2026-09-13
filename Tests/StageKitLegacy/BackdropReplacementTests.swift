import AppKit
import ImageIO
import UniformTypeIdentifiers

final class BackdropReplacementTests {
    private func temporary() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("BackdropReplacementTests-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }
    private func png(_ color: NSColor, width: Int = 120, height: Int = 80, asymmetric: Bool = false) -> Data {
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        let rgb = color.usingColorSpace(.sRGB)!
        let solid = [UInt8(rgb.redComponent * 255), UInt8(rgb.greenComponent * 255), UInt8(rgb.blueComponent * 255), UInt8(255)]
        let pixels = bitmap.bitmapData!
        for y in 0..<height { for x in 0..<width {
            // Asymmetric gradients expose crop direction, zoom and rotation.
            let components = asymmetric ? [UInt8(x * 255 / width), UInt8(y * 255 / height), UInt8((x + 2 * y) * 255 / (width + 2 * height)), UInt8(255)] : solid
            for c in 0..<4 { pixels[y * bitmap.bytesPerRow + x * 4 + c] = components[c] }
        } }
        return bitmap.representation(using: .png, properties: [:])!
    }
    private func rotatedJPEG() throws -> Data {
        let source = CGImageSourceCreateWithData(png(.black, width: 420, height: 180, asymmetric: true) as CFData, nil)!
        let image = CGImageSourceCreateImageAtIndex(source, 0, nil)!
        let output = NSMutableData()
        let destination = CGImageDestinationCreateWithData(output, UTType.jpeg.identifier as CFString, 1, nil)!
        let properties: [CFString: Any] = [kCGImagePropertyOrientation: 6, kCGImageDestinationLossyCompressionQuality: 0.95]
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw SceneError.invalidImage }
        return output as Data
    }
    private func makeModel(_ root: URL, scene: DemoScene? = nil) throws -> DemoScenes {
        try png(.systemRed).write(to: root.appendingPathComponent("original.png"))
        try SceneStorage.save([scene ?? DemoScene(name: "Saved customer", background: "original.png")], to: root.appendingPathComponent("scenes.json"))
        return DemoScenes(root: root, systemIntegrationEnabled: false)
    }
    private func files(_ root: URL) throws -> [String: Data] {
        var result: [String: Data] = [:]
        for url in try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: [.isRegularFileKey]) {
            if try url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true {
                result[url.lastPathComponent] = try Data(contentsOf: url)
            }
        }
        return result
    }

    func testDraftCropChoiceAndCancelNeverWrite() throws {
        let root = try temporary(); defer { try? FileManager.default.removeItem(at: root) }
        var original = DemoScene(name: "Keep my layout", background: "original.png")
        original.backgroundX = 0.2; original.backgroundY = 0.8; original.zoom = 1.4
        let model = try makeModel(root, scene: original)
        let source = root.appendingPathComponent("candidate.png"); try png(.systemBlue).write(to: source)
        let before = try files(root)
        let draft = BackdropReplacement(scene: original, root: root)
        XCTAssertEqual(draft.x, 0.2); XCTAssertEqual(draft.y, 0.8); XCTAssertEqual(draft.zoom, 1.4)
        XCTAssertFalse(draft.canApply)
        draft.centreCrop(); XCTAssertTrue(draft.canApply)
        XCTAssertEqual(draft.previewScene(current: original).phoneX, original.phoneX)
        try draft.chooseImage(source)
        XCTAssertEqual(draft.x, 0.5); XCTAssertEqual(draft.y, 0.5); XCTAssertEqual(draft.zoom, 1)
        draft.x = 0.7; draft.zoom = 1.8
        try draft.chooseImage(source)
        XCTAssertEqual(draft.x, 0.7, "Choosing the same picture twice keeps its crop")
        XCTAssertEqual(draft.zoom, 1.8)
        XCTAssertEqual(try files(root), before, "Choosing, cropping and previewing must not create a durable file")
        draft.cancel(); draft.cancel()
        XCTAssertFalse(draft.canApply); XCTAssertTrue(draft.candidate == nil)
        XCTAssertThrowsError(try model.applyBackdrop(draft))
        XCTAssertThrowsError(try draft.chooseImage(source))
        XCTAssertEqual(try files(root), before, "Cancel and late callbacks must leave all saved bytes unchanged")
    }

    func testImportedCommitPreservesCurrentForegroundAndOriginals() throws {
        let root = try temporary(); defer { try? FileManager.default.removeItem(at: root) }
        let model = try makeModel(root)
        let original = model.selected!
        let source = root.appendingPathComponent("download.png"); let replacement = png(.systemBlue)
        try replacement.write(to: source)
        let draft = BackdropReplacement(scene: original, root: root)
        try draft.chooseImage(source); draft.x = 0.3; draft.y = 0.9; draft.zoom = 1.2
        try FileManager.default.removeItem(at: source)
        var newer = original
        newer.name = "Newer name"; newer.phoneX = 0.12; newer.phoneY = 0.8; newer.phoneHeight = 0.75
        newer.viewport = .tablet; newer.logo = SceneLogo(image: "logo.png")
        newer.persona = PersonaPlacement(image: "persona.png"); newer.hand = SceneHand(image: "hand.png")
        // Simulate a newer saved edit while this model's preview remains open.
        try SceneStorage.save([newer], to: root.appendingPathComponent("scenes.json"))
        let oldBytes = try Data(contentsOf: root.appendingPathComponent(original.background))
        try model.applyBackdrop(draft)
        let applied = model.scenes.first!
        var expected = newer; expected.background = applied.background
        expected.backgroundX = 0.3; expected.backgroundY = 0.9; expected.zoom = 1.2
        XCTAssertEqual(applied, expected)
        XCTAssertEqual(model.scenes.count, 1); XCTAssertEqual(applied.id, original.id)
        XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent(applied.background)), replacement,
                       "Applying uses the previewed bytes even if the download was removed")
        XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent(original.background)), oldBytes)
        XCTAssertEqual(try SceneStorage.load(root.appendingPathComponent("scenes.json")), [expected])
        XCTAssertFalse(draft.active); XCTAssertThrowsError(try model.applyBackdrop(draft))
        XCTAssertFalse(model.hasDesktopSnapshot); XCTAssertFalse(model.isPresenting)
    }

    func testSavedReuseDeduplicationAndMissingBackdropRepair() throws {
        let root = try temporary(); defer { try? FileManager.default.removeItem(at: root) }
        let model = try makeModel(root)
        let original = model.selected!
        try png(.systemBlue).write(to: root.appendingPathComponent("blue.png"))
        try png(.systemBlue).write(to: root.appendingPathComponent("same-blue.png"))
        let blue = DemoScene(name: "Blue customer", background: "blue.png")
        let repeatBlue = DemoScene(name: "Repeat image", background: "same-blue.png")
        var duplicate = original; duplicate.id = UUID(); duplicate.name = "Original duplicate"
        let missing = DemoScene(name: "Repair this layout", background: "missing.png")
        try SceneStorage.save([original, duplicate, blue, repeatBlue, missing], to: root.appendingPathComponent("scenes.json"))
        let current = DemoScenes(root: root, systemIntegrationEnabled: false)
        let choices = BackdropChoices.saved(scenes: current.scenes, root: root, preferred: original)
        XCTAssertEqual(choices.count, 3, "Repeated references appear once; different files remain independently reusable")
        var cancellationChecks = 0
        let cancelled = BackdropChoices.saved(scenes: current.scenes, root: root, preferred: original, isCancelled: {
            cancellationChecks += 1
            return cancellationChecks >= 3
        })
        XCTAssertEqual(cancelled.count, 1, "Cancel stops before decoding the remaining gallery")
        XCTAssertEqual(cancellationChecks, 3)
        XCTAssertTrue(BackdropChoices.saved(scenes: current.scenes, root: root, preferred: original, isCancelled: { true }).isEmpty)
        XCTAssertTrue(BackdropChoices.starters(SceneStarters.all, isCancelled: { true }).isEmpty)
        let chosen = choices.first { $0.existingFilename == "blue.png" }!
        let draft = BackdropReplacement(scene: missing, root: root)
        XCTAssertTrue(draft.candidate == nil); XCTAssertFalse(draft.canApply)
        try draft.choose(chosen)
        let namesBefore = Set(try files(root).keys)
        try current.applyBackdrop(draft)
        XCTAssertEqual(Set(try files(root).keys), namesBefore, "Reusing an existing image must not copy it")
        XCTAssertEqual(current.scenes.first { $0.id == missing.id }?.background, "blue.png")
        XCTAssertEqual(current.scenes.first { $0.id == duplicate.id }, duplicate)
        XCTAssertEqual(current.scenes.count, 5)
        let noChange = BackdropReplacement(scene: original, root: root)
        try noChange.chooseImage(root.appendingPathComponent(original.background))
        XCTAssertFalse(noChange.canApply, "Choosing the original file again is not a change")
        // A selected original deleted after opening can still be repaired from
        // an explicitly chosen copy; it must not bind back to the missing path.
        let backup = root.appendingPathComponent("backup.png")
        try png(.systemRed).write(to: backup)
        try FileManager.default.removeItem(at: root.appendingPathComponent(original.background))
        try noChange.chooseImage(backup)
        XCTAssertTrue(noChange.canApply); XCTAssertTrue(noChange.candidate?.existingFilename == nil)
    }

    func testStaleDeletedInvalidAndBlockedApplyPreserveBytes() throws {
        let root = try temporary(); defer { try? FileManager.default.removeItem(at: root) }
        let model = try makeModel(root), original = model.selected!
        let source = root.appendingPathComponent("candidate.png"); try png(.systemBlue).write(to: source)
        let archive = root.appendingPathComponent("scenes.json")
        let draft = BackdropReplacement(scene: original, root: root); try draft.chooseImage(source)
        var changed = original; changed.backgroundX = 0.7
        try SceneStorage.save([changed], to: archive)
        var before = try files(root)
        XCTAssertThrowsError(try model.applyBackdrop(draft)); XCTAssertEqual(try files(root), before)
        try SceneStorage.save([], to: archive); before = try files(root)
        XCTAssertThrowsError(try model.applyBackdrop(draft)); XCTAssertEqual(try files(root), before)
        for bytes in [Data("malformed scene archive".utf8), Data("{\"version\":999,\"scenes\":[]}".utf8)] {
            try bytes.write(to: archive); before = try files(root)
            XCTAssertThrowsError(try model.applyBackdrop(draft)); XCTAssertEqual(try files(root), before)
        }
        try SceneStorage.save([original], to: archive)
        let blocked = DemoScenes(root: root, readOnlyReason: "Fixture read-only", systemIntegrationEnabled: false)
        before = try files(root)
        XCTAssertThrowsError(try blocked.applyBackdrop(draft)); XCTAssertEqual(try files(root), before)
        let invalid = root.appendingPathComponent("invalid.png"); try Data("not an image".utf8).write(to: invalid)
        let previous = draft.candidate?.image.digest
        XCTAssertThrowsError(try draft.chooseImage(invalid))
        XCTAssertEqual(draft.candidate?.image.digest, previous)
        draft.zoom = .nan; XCTAssertFalse(draft.canApply)
        XCTAssertThrowsError(try model.applyBackdrop(draft))
        XCTAssertThrowsError(try BackdropImage.decode(Data(repeating: 0, count: BackdropImage.maximumBytes + 1)))
    }

    func testCommitFailureCleansOnlyNewCopyAndChangedSavedImageRejects() throws {
        let root = try temporary(); defer { try? FileManager.default.removeItem(at: root) }
        let model = try makeModel(root), original = model.selected!
        let source = root.appendingPathComponent("candidate.png"); try png(.systemBlue).write(to: source)
        let draft = BackdropReplacement(scene: original, root: root); try draft.chooseImage(source)
        let archive = root.appendingPathComponent("scenes.json"), before = try files(root)
        // The folder remains writable for the new image; only replacing the
        // existing archive fails, exercising rollback after the image copy.
        try FileManager.default.setAttributes([.immutable: true], ofItemAtPath: archive.path)
        defer { try? FileManager.default.setAttributes([.immutable: false], ofItemAtPath: archive.path) }
        XCTAssertThrowsError(try model.applyBackdrop(draft))
        XCTAssertEqual(try files(root), before); XCTAssertTrue(draft.active)
        try FileManager.default.setAttributes([.immutable: false], ofItemAtPath: archive.path)
        let saved = BackdropReplacement(scene: original, root: root); saved.x = 0.4
        try png(.systemGreen).write(to: root.appendingPathComponent(original.background))
        let changed = try files(root)
        XCTAssertThrowsError(try model.applyBackdrop(saved)); XCTAssertEqual(try files(root), changed)
        // The same imported preview can be retried after a failed save.
        try model.applyBackdrop(draft); XCTAssertEqual(model.scenes.count, 1)
    }

    func testPreviewAndSavedRenderingAtSameAspectKeepForeground() throws {
        let root = try temporary(); defer { try? FileManager.default.removeItem(at: root) }
        var original = DemoScene(name: "Composed scene", background: "original.png")
        original.showsPhone = false
        original.logo = SceneLogo(image: "logo.png"); original.logo!.corner = .topLeft; original.logo!.width = 0.2
        original.persona = PersonaPlacement(image: "persona.png", x: 1, y: 0, width: 0.2)
        try png(.systemGreen, width: 100, height: 40).write(to: root.appendingPathComponent("logo.png"))
        try png(.systemYellow, width: 60, height: 90).write(to: root.appendingPathComponent("persona.png"))
        let model = try makeModel(root, scene: original)
        let inputs = [("wide.png", png(.black, width: 400, height: 120, asymmetric: true)),
                      ("portrait.png", png(.black, width: 140, height: 420, asymmetric: true)),
                      ("rotated.jpg", try rotatedJPEG())]
        let size = CGSize(width: 360, height: 240)
        for (name, data) in inputs {
            let source = root.appendingPathComponent(name); try data.write(to: source)
            let current = model.scenes.first!
            let draft = BackdropReplacement(scene: current, root: root); try draft.chooseImage(source)
            draft.x = 0.75; draft.y = 0.2; draft.zoom = 1.3
            let view = BackdropScenePreviewView(frame: CGRect(origin: .zero, size: size))
            view.scene = draft.previewScene(current: current); view.image = draft.candidate!.image.image
            view.logo = model.logoImage(for: current); view.persona = model.personaImage(for: current)
            let preview = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 360, pixelsHigh: 240, bitsPerSample: 8,
                samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
            NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: preview)
            view.draw(view.bounds); NSGraphicsContext.restoreGraphicsState()
            // Decode both snapshots as PNG so profile tagging happens equally;
            // comparing an untagged in-memory bitmap to a PNG changes color space.
            let previewPNG = NSBitmapImageRep(data: preview.representation(using: .png, properties: [:])!)!
            if name == "rotated.jpg" { XCTAssertTrue(view.image!.size.height > view.image!.size.width, "EXIF orientation is applied before crop") }
            try model.applyBackdrop(draft)
            let applied = model.scenes.first!
            let rendered = NSBitmapImageRep(data: try model.renderPNG(applied, image: model.image(for: applied)!, size: size))!
            let backgroundPoints = [CGPoint(x: 30, y: 40), CGPoint(x: 180, y: 120), CGPoint(x: 320, y: 210)]
            let foregroundPoints = [SceneRenderer.logoRect(applied.logo!, imageSize: view.logo!.size, in: size).centre,
                                    PersonaGeometry.rect(applied.persona!, imageSize: view.persona!.size, in: size).centre]
            for point in backgroundPoints + foregroundPoints {
                let a = previewPNG.colorAt(x: Int(point.x), y: 239 - Int(point.y))!.usingColorSpace(.sRGB)!
                let b = rendered.colorAt(x: Int(point.x), y: 239 - Int(point.y))!.usingColorSpace(.sRGB)!
                XCTAssertEqual(Double(a.redComponent), Double(b.redComponent), accuracy: 0.04)
                XCTAssertEqual(Double(a.greenComponent), Double(b.greenComponent), accuracy: 0.04)
                XCTAssertEqual(Double(a.blueComponent), Double(b.blueComponent), accuracy: 0.04)
            }
            // These foreground pixels must be actual artwork, not two equally
            // blank outputs passing a parity comparison.
            let green = rendered.colorAt(x: Int(foregroundPoints[0].x), y: 239 - Int(foregroundPoints[0].y))!.usingColorSpace(.sRGB)!
            XCTAssertGreaterThan(green.greenComponent, green.redComponent + 0.15)
            XCTAssertGreaterThan(green.greenComponent, green.blueComponent + 0.15)
            let yellow = rendered.colorAt(x: Int(foregroundPoints[1].x), y: 239 - Int(foregroundPoints[1].y))!.usingColorSpace(.sRGB)!
            XCTAssertGreaterThan(yellow.redComponent, yellow.blueComponent + 0.4)
            XCTAssertGreaterThan(yellow.greenComponent, yellow.blueComponent + 0.4)
            XCTAssertEqual(applied.logo, original.logo); XCTAssertEqual(applied.persona, original.persona)
        }
    }
}

private extension CGRect {
    var centre: CGPoint { CGPoint(x: midX, y: midY) }
}
