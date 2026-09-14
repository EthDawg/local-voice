import AppKit
import SceneSyncKit
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
        // Foundation expands /var to /private/var when enumerating temporary
        // directories. Use the same root spelling for stable relative keys.
        let canonicalRoot = root.standardizedFileURL
        let enumerator = FileManager.default.enumerator(at: canonicalRoot, includingPropertiesForKeys: [.isRegularFileKey])!
        for case let url as URL in enumerator {
            if try url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true {
                let path = url.standardizedFileURL.path
                result[String(path.dropFirst(canonicalRoot.path.count + 1))] = try Data(contentsOf: url)
            }
        }
        return result
    }
    private func assertFailedCommitPreserves(_ before: [String: Data], in root: URL) throws {
        let after = try files(root)
        for (name, bytes) in before { XCTAssertEqual(after[name], bytes, "Failed commit changed " + name) }
        let added = Set(after.keys).subtracting(before.keys)
        XCTAssertTrue(added.count <= 1, "Only the candidate's unused canonical asset may remain")
        for name in added {
            XCTAssertTrue(name.hasPrefix("Portable/Assets/"), "A failed commit must remove its new renderer/source copy")
            XCTAssertTrue((try? SceneAsset.validate(after[name]!, named: URL(fileURLWithPath: name).lastPathComponent)) != nil)
        }
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
        let model = try makeModel(root), original = model.selected!
        let legacy = try Data(contentsOf: root.appendingPathComponent("scenes.json"))
        let source = root.appendingPathComponent("download.png"), replacement = png(.systemBlue)
        try replacement.write(to: source)
        let draft = BackdropReplacement(scene: original, root: root)
        try draft.chooseImage(source); draft.x = 0.3; draft.y = 0.9; draft.zoom = 1.2
        try FileManager.default.removeItem(at: source)
        for (name, colour) in [("logo.png", NSColor.systemGreen), ("persona.png", .systemYellow), ("hand.png", .systemOrange)] {
            try png(colour).write(to: root.appendingPathComponent(name))
        }
        var newer = original
        newer.name = "Newer name"; newer.phoneX = 0.12; newer.phoneY = 0.8; newer.phoneHeight = 0.75
        newer.viewport = .tablet; newer.logo = SceneLogo(image: "logo.png")
        newer.persona = PersonaPlacement(image: "persona.png"); newer.hand = SceneHand(image: "hand.png")
        XCTAssertTrue(model.update(newer), "A canonical foreground edit happens while its backdrop preview stays open")
        newer = model.selected!
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
        XCTAssertEqual(DemoScenes(root: root, systemIntegrationEnabled: false).scenes, [expected])
        XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent("scenes.json")), legacy)
        XCTAssertFalse(draft.active); XCTAssertThrowsError(try model.applyBackdrop(draft))
        XCTAssertFalse(model.hasDesktopSnapshot); XCTAssertFalse(model.isPresenting)
    }

    func testPhotoHandoffPreviewTargetsChosenSceneAndKeepsIndependentCopy() throws {
        let root = try temporary(), inbox = try temporary()
        defer { try? FileManager.default.removeItem(at: root); try? FileManager.default.removeItem(at: inbox) }
        let model = try makeModel(root), first = model.selected!
        let legacy = try Data(contentsOf: root.appendingPathComponent("scenes.json"))
        for (name, colour) in [("logo.png", NSColor.systemGreen), ("persona.png", .systemYellow)] {
            try png(colour).write(to: root.appendingPathComponent(name))
        }
        var second = first; second.id = UUID(); second.name = "Chosen scene"; second.phoneX = 0.7; second.libraryRevision = nil
        second.logo = SceneLogo(image: "logo.png"); second.persona = PersonaPlacement(image: "persona.png")
        try MainActor.assumeIsolated { try model.sceneSync!.create(second) }
        second = model.scenes.first { $0.id == second.id }!
        model.selectedID = first.id
        let source = inbox.appendingPathComponent("received.jpg"), bytes = try rotatedJPEG()
        try bytes.write(to: source)
        let before = try files(root)
        let cancelled = try model.makeBackdropReplacement(sceneID: second.id, imageURL: source, title: "Photo from iPhone")
        XCTAssertEqual(cancelled.sceneID, second.id)
        XCTAssertEqual(model.selectedID, first.id, "Preparing another scene must not change the library selection")
        XCTAssertEqual(try files(root), before, "The handoff seam must not copy or save until Apply")
        cancelled.cancel(); XCTAssertEqual(try files(root), before); XCTAssertEqual(try Data(contentsOf: source), bytes)
        let draft = try model.makeBackdropReplacement(sceneID: second.id, imageURL: source, title: "Photo from iPhone")
        var newer = second; newer.name = "Later name"; newer.phoneX = 0.18; newer.persona?.width = 0.25
        XCTAssertTrue(model.update(newer)); newer = model.scenes.first { $0.id == second.id }!
        try FileManager.default.removeItem(at: source); try model.applyBackdrop(draft)
        let saved = model.scenes.first { $0.id == second.id }!
        var expected = newer; expected.background = saved.background
        expected.backgroundX = 0.5; expected.backgroundY = 0.5; expected.zoom = 1
        XCTAssertEqual(saved, expected, "Only the chosen scene's backdrop may change, preserving later foreground edits")
        XCTAssertEqual(model.scenes.first { $0.id == first.id }, first); XCTAssertEqual(model.scenes.count, 2)
        XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent(saved.background)), bytes,
                       "The scene owns an independent previewed copy after the inbox source disappears")
        XCTAssertFalse(model.hasDesktopSnapshot); XCTAssertFalse(model.isPresenting)
        XCTAssertThrowsError(try model.makeBackdropReplacement(sceneID: UUID(), imageURL: source, title: "Missing"))
        let blocked = DemoScenes(root: root, readOnlyReason: "Unreadable fixture", systemIntegrationEnabled: false)
        XCTAssertThrowsError(try blocked.makeBackdropReplacement(sceneID: second.id, imageURL: source, title: "Blocked"))
        XCTAssertEqual(DemoScenes(root: root, systemIntegrationEnabled: false).scenes, model.scenes)
        XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent("scenes.json")), legacy)
    }

    func testSavedReuseDeduplicationAndMissingBackdropRepair() throws {
        let root = try temporary(); defer { try? FileManager.default.removeItem(at: root) }
        try png(.systemRed).write(to: root.appendingPathComponent("original.png"))
        try png(.systemBlue).write(to: root.appendingPathComponent("blue.png")); try png(.systemBlue).write(to: root.appendingPathComponent("same-blue.png"))
        let original = DemoScene(name: "Original", background: "original.png")
        let blue = DemoScene(name: "Blue customer", background: "blue.png"), repeatBlue = DemoScene(name: "Repeat image", background: "same-blue.png")
        var duplicate = original; duplicate.id = UUID(); duplicate.name = "Original duplicate"
        let missing = DemoScene(name: "Repair this layout", background: "missing.png")
        let legacyURL = root.appendingPathComponent("scenes.json")
        try SceneStorage.save([original, duplicate, blue, repeatBlue, missing], to: legacyURL)
        let legacy = try Data(contentsOf: legacyURL), current = DemoScenes(root: root, systemIntegrationEnabled: false)
        let preferred = current.scenes.first { $0.id == original.id }!, keptDuplicate = current.scenes.first { $0.id == duplicate.id }!
        let choices = BackdropChoices.saved(scenes: current.scenes, root: root, preferred: preferred)
        XCTAssertEqual(choices.count, 2, "Identical immutable artwork has one saved choice even when imported from different files")
        var cancellationChecks = 0
        let cancelled = BackdropChoices.saved(scenes: current.scenes, root: root, preferred: preferred, isCancelled: {
            cancellationChecks += 1; return cancellationChecks >= 3
        })
        XCTAssertEqual(cancelled.count, 1); XCTAssertEqual(cancellationChecks, 3)
        XCTAssertTrue(BackdropChoices.saved(scenes: current.scenes, root: root, preferred: preferred, isCancelled: { true }).isEmpty)
        XCTAssertTrue(BackdropChoices.starters(SceneStarters.all, isCancelled: { true }).isEmpty)
        let blueFile = current.scenes.first { $0.id == blue.id }!.background
        let chosen = choices.first { $0.existingFilename == blueFile }!
        let incomplete = BackdropReplacement(scene: missing, root: root)
        XCTAssertTrue(incomplete.candidate == nil); XCTAssertFalse(incomplete.canApply); try incomplete.choose(chosen)
        let beforeRecovery = try files(root)
        // Unmigrated recovery entries cannot be silently rewritten.
        XCTAssertThrowsError(try current.applyBackdrop(incomplete))
        XCTAssertEqual(try files(root), beforeRecovery)
        try png(.systemBlue).write(to: root.appendingPathComponent("missing.png"))
        MainActor.assumeIsolated { current.sceneSync!.migratePreviousScenes() }
        XCTAssertEqual(current.scenes.first { $0.id == missing.id }?.background, blueFile)
        XCTAssertFalse(current.isSceneReadOnly(current.scenes.first { $0.id == missing.id }!))
        let draft = BackdropReplacement(scene: preferred, root: root); try draft.choose(chosen)
        let namesBefore = Set(try files(root).keys); try current.applyBackdrop(draft)
        XCTAssertEqual(Set(try files(root).keys), namesBefore, "Reusing an existing canonical image creates no new image file")
        XCTAssertEqual(current.scenes.first { $0.id == original.id }?.background, blueFile)
        XCTAssertEqual(current.scenes.first { $0.id == duplicate.id }, keptDuplicate); XCTAssertEqual(current.scenes.count, 5)
        XCTAssertEqual(try Data(contentsOf: legacyURL), legacy)
        let noChange = BackdropReplacement(scene: keptDuplicate, root: root)
        try noChange.chooseImage(root.appendingPathComponent(keptDuplicate.background)); XCTAssertFalse(noChange.canApply)
        let backup = root.appendingPathComponent("backup.png"); try png(.systemRed).write(to: backup)
        try FileManager.default.removeItem(at: root.appendingPathComponent(keptDuplicate.background))
        try noChange.chooseImage(backup)
        XCTAssertTrue(noChange.canApply); XCTAssertTrue(noChange.candidate?.existingFilename == nil)
    }

    func testStaleDeletedInvalidAndBlockedApplyPreserveBytes() throws {
        let root = try temporary(); defer { try? FileManager.default.removeItem(at: root) }
        let model = try makeModel(root), original = model.selected!
        let source = root.appendingPathComponent("candidate.png"); try png(.systemBlue).write(to: source)
        let draft = BackdropReplacement(scene: original, root: root); try draft.chooseImage(source)
        var changed = original; changed.backgroundX = 0.7; XCTAssertTrue(model.update(changed))
        var before = try files(root)
        XCTAssertThrowsError(try model.applyBackdrop(draft)); XCTAssertEqual(try files(root), before)
        model.remove(); before = try files(root)
        XCTAssertThrowsError(try model.applyBackdrop(draft)); XCTAssertEqual(try files(root), before)
        var future = SceneLibraryArchive(); future.version = 999
        let futureBytes = try JSONEncoder().encode(future)
        for bytes in [Data("malformed scene archive".utf8), futureBytes] {
            let caseRoot = try temporary(); defer { try? FileManager.default.removeItem(at: caseRoot) }
            let owner = try makeModel(caseRoot), preview = BackdropReplacement(scene: owner.selected!, root: caseRoot)
            try preview.chooseImage(source)
            let archive = caseRoot.appendingPathComponent("Portable/scene-library.json")
            try bytes.write(to: archive); let untouched = try files(caseRoot)
            XCTAssertThrowsError(try owner.applyBackdrop(preview))
            try assertFailedCommitPreserves(untouched, in: caseRoot)
            XCTAssertEqual(try Data(contentsOf: archive), bytes)
            let blockedByArchive = DemoScenes(root: caseRoot, systemIntegrationEnabled: false)
            XCTAssertTrue(blockedByArchive.storageBlocked); XCTAssertNotNil(blockedByArchive.notice)
            if bytes == futureBytes {
                XCTAssertEqual(MainActor.assumeIsolated { blockedByArchive.sceneSync!.library.error }, SceneDocumentError.futureVersion.localizedDescription)
            }
        }
        let blocked = DemoScenes(root: root, readOnlyReason: "Fixture read-only", systemIntegrationEnabled: false)
        before = try files(root); XCTAssertThrowsError(try blocked.applyBackdrop(draft)); XCTAssertEqual(try files(root), before)
        let invalid = root.appendingPathComponent("invalid.png"); try Data("not an image".utf8).write(to: invalid)
        let previous = draft.candidate?.image.digest
        XCTAssertThrowsError(try draft.chooseImage(invalid)); XCTAssertEqual(draft.candidate?.image.digest, previous)
        draft.zoom = .nan; XCTAssertFalse(draft.canApply); XCTAssertThrowsError(try model.applyBackdrop(draft))
        XCTAssertThrowsError(try BackdropImage.decode(Data(repeating: 0, count: BackdropImage.maximumBytes + 1)))
    }

    func testCommitFailureCleansOnlyNewCopyAndChangedSavedImageRejects() throws {
        let root = try temporary(); defer { try? FileManager.default.removeItem(at: root) }
        let model = try makeModel(root), original = model.selected!
        let source = root.appendingPathComponent("candidate.png"); try png(.systemBlue).write(to: source)
        let draft = BackdropReplacement(scene: original, root: root); try draft.chooseImage(source)
        let archive = root.appendingPathComponent("Portable/scene-library.json"), before = try files(root)
        try FileManager.default.setAttributes([.immutable: true], ofItemAtPath: archive.path)
        defer { try? FileManager.default.setAttributes([.immutable: false], ofItemAtPath: archive.path) }
        XCTAssertThrowsError(try model.applyBackdrop(draft))
        try assertFailedCommitPreserves(before, in: root); XCTAssertTrue(draft.active)
        XCTAssertEqual(try Data(contentsOf: archive), before["Portable/scene-library.json"])
        try FileManager.default.setAttributes([.immutable: false], ofItemAtPath: archive.path)
        // A failed canonical commit pauses that store instance. Reopening loads
        // its preserved manifest before retrying the same independent preview.
        let reopened = DemoScenes(root: root, systemIntegrationEnabled: false)
        let saved = BackdropReplacement(scene: reopened.selected!, root: root); saved.x = 0.4
        let imageURL = root.appendingPathComponent(original.background), originalBytes = try Data(contentsOf: root.appendingPathComponent(original.background))
        try png(.systemGreen).write(to: imageURL)
        let changed = try files(root)
        XCTAssertThrowsError(try reopened.applyBackdrop(saved)); XCTAssertEqual(try files(root), changed)
        try originalBytes.write(to: imageURL)
        try reopened.applyBackdrop(draft); XCTAssertEqual(reopened.scenes.count, 1)
        XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent(reopened.selected!.background)), png(.systemBlue))
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
            XCTAssertEqual(applied.logo, current.logo); XCTAssertEqual(applied.persona, current.persona)
            XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent(applied.logo!.image)), try Data(contentsOf: root.appendingPathComponent(original.logo!.image)))
            XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent(applied.persona!.image)), try Data(contentsOf: root.appendingPathComponent(original.persona!.image)))
        }
    }
}

private extension CGRect {
    var centre: CGPoint { CGPoint(x: midX, y: midY) }
}
