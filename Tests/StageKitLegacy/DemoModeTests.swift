import AppKit

final class DemoModeTests {
    func testPresentationControlsRevealAndRetention() {
        var policy = PresentationControlsPolicy()
        policy.reveal(at: 0)
        XCTAssertEqual(policy.hideDeadline, 4)
        policy.pointerMoved(y: 200, at: 3)
        XCTAssertEqual(policy.hideDeadline, 4, "Moving over the demo does not postpone hiding")
        policy.hideIfDue(at: 3.9)
        XCTAssertTrue(policy.isVisible)
        policy.hideIfDue(at: 4)
        XCTAssertFalse(policy.isVisible)
        policy.pointerMoved(y: 300, at: 5)
        XCTAssertFalse(policy.isVisible, "Ordinary pointer movement cannot reveal the toolbar")
        policy.pointerMoved(y: 12, at: 6)
        XCTAssertTrue(policy.isVisible)
        XCTAssertTrue(policy.hideDeadline == nil, "Top-edge intent retains the controls")
        policy.pointerMoved(y: 60, at: 7)
        XCTAssertEqual(policy.hideDeadline, 11)
        policy.pointerMoved(y: 700, at: 8)
        XCTAssertEqual(policy.hideDeadline, 11, "Only leaving the edge starts a new idle period")
        policy.hideIfDue(at: 11)
        XCTAssertFalse(policy.isVisible)

        for hold in [PresentationControlsPolicy.Hold.toolbarHover, .keyboardFocus, .sheet, .pinned, .voiceOver] {
            policy.setHold(hold, active: true, at: 20)
            policy.hideIfDue(at: 100)
            XCTAssertTrue(policy.isVisible, "Controls remain visible during \(hold)")
            XCTAssertTrue(policy.hideDeadline == nil)
            policy.setHold(hold, active: false, at: 101)
            XCTAssertEqual(policy.hideDeadline, 105)
            policy.hideIfDue(at: 105)
            XCTAssertFalse(policy.isVisible)
        }
        policy.setHold(.toolbarHover, active: true, at: 110)
        policy.setHold(.sheet, active: true, at: 111)
        policy.setHold(.toolbarHover, active: false, at: 112)
        policy.hideIfDue(at: 200)
        XCTAssertTrue(policy.isVisible, "Leaving the toolbar cannot hide an open sheet")
        policy.setHold(.sheet, active: false, at: 201)
        policy.reveal(at: 203)
        policy.hideIfDue(at: 205)
        XCTAssertTrue(policy.isVisible, "An old timer cannot undo a more recent reveal")
        policy.hideIfDue(at: 207)
        XCTAssertFalse(policy.isVisible)
        policy.reveal(at: 210)
        XCTAssertTrue(policy.isVisible, "The keyboard can reveal controls while hidden")
        XCTAssertTrue(PresentationControlsPolicy.isRevealCommand(characters: "/", command: true, option: false, control: false))
        XCTAssertFalse(PresentationControlsPolicy.isRevealCommand(characters: "r", command: true, option: false, control: false), "Reconnect remains its own command")
        XCTAssertFalse(PresentationControlsPolicy.isRevealCommand(characters: "\u{1b}", command: false, option: false, control: false), "Escape remains its own command")
        XCTAssertFalse(PresentationControlsPolicy.isRevealCommand(characters: "/", command: false, option: false, control: false))
        XCTAssertFalse(PresentationControlsPolicy.isRevealCommand(characters: "/", command: true, option: true, control: false))
        XCTAssertFalse(PresentationControlsPolicy.isRevealCommand(characters: "/", command: true, option: false, control: true))
    }
    private func temporary() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("DemoModeTests-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true); return root
    }
    func testViewportGeometryAndProfiles() throws {
        for size in [CGSize(width: 1920, height: 1080), CGSize(width: 1080, height: 1920), CGSize(width: 2940, height: 1912)] {
            for viewport in [DeviceViewport.phone, .tablet, .landscape, .legacy, DeviceViewport(aspect: 2.4, border: 0.035, corners: 0.3)] {
                for position in [0.0, 0.5, 1.0] {
                    var scene = DemoScene(background: "image.png"); scene.viewport = viewport
                    scene.phoneX = position; scene.phoneY = position; scene.phoneHeight = 0.96
                    let geometry = ViewportGeometry(scene: scene, size: size)
                    XCTAssertTrue(CGRect(origin: .zero, size: size).insetBy(dx: -0.001, dy: -0.001).contains(geometry.outer))
                    XCTAssertTrue(geometry.outer.contains(geometry.screen))
                    XCTAssertEqual(geometry.screen.width / geometry.screen.height, viewport.aspect, accuracy: 0.00001)
                    XCTAssertEqual(geometry.outerRadius - geometry.innerRadius, geometry.border, accuracy: 0.00001)
                }
            }
        }
        var invalid = DeviceViewport(); invalid.corners = .infinity
        XCTAssertThrowsError(try invalid.validated())
        let root = try temporary(); defer { try? FileManager.default.removeItem(at: root) }
        var scene = DemoScene(background: "image.png"); scene.viewport = .tablet
        try SceneStorage.save([scene], to: root.appendingPathComponent("scenes.json"))
        let model = DemoScenes(root: root); model.saveMyDevice()
        let reopened = DemoScenes(root: root)
        XCTAssertEqual(reopened.myDevice, .tablet)
        XCTAssertEqual(reopened.selected?.viewport, .tablet)
        let backdrop = root.appendingPathComponent("source.png")
        try SceneLibraryStorage.textLogo("Backdrop").write(to: backdrop)
        try reopened.addImage(backdrop)
        XCTAssertEqual(reopened.selected?.viewport, .tablet, "New scenes start with the saved device shape")
    }
    func testIndependentSpaceRecoveryAndManualChanges() throws {
        let original = URL(fileURLWithPath: "/original.heic")
        let a = URL(fileURLWithPath: "/a.png"), b = URL(fileURLWithPath: "/b.png"), c = URL(fileURLWithPath: "/c.png")
        func snapshot(_ applied: URL) -> DesktopSnapshot { DesktopSnapshot(screenID: "same-display", originalURL: original, appliedURL: applied) }
        let first = DesktopRecovery.preparing([], screenID: "same-display", current: original, output: a, original: snapshot(a))
        let second = DesktopRecovery.preparing(first, screenID: "same-display", current: original, output: b, original: snapshot(b))
        XCTAssertEqual(second.count, 2, "Two Spaces on the same monitor must retain two recovery chains")
        let third = DesktopRecovery.preparing(second, screenID: "same-display", current: a, output: c, original: snapshot(c))
        XCTAssertEqual(third.count, 2)
        XCTAssertEqual(third[0].originalURL, original)
        XCTAssertTrue(third[0].owns(a)); XCTAssertTrue(third[0].owns(c)); XCTAssertTrue(third[1].owns(b))
        let archived = try JSONDecoder().decode([DesktopSnapshot].self, from: JSONEncoder().encode(third))
        let plan = DesktopRecovery.plan(archived, current: ["same-display": c])
        XCTAssertEqual(plan.ready.count, 1); XCTAssertEqual(plan.retained.count, 1)
        XCTAssertTrue(plan.retained[0].owns(b), "Restoring one Space must never discard another")
        let next = DesktopRecovery.plan(plan.retained, current: ["same-display": b])
        XCTAssertEqual(next.ready.count, 1); XCTAssertTrue(next.retained.isEmpty)
        let manual = DesktopRecovery.plan(archived, current: ["same-display": URL(fileURLWithPath: "/user-new.jpg")])
        XCTAssertTrue(manual.ready.isEmpty); XCTAssertEqual(manual.retained.count, 2)
        XCTAssertEqual(DesktopRecovery.plan(archived, current: [:]).retained.count, 2)
    }
    func testCaptureSourceIdentityAndStaleFrames() {
        let phone = DemoSource(id: "phone", name: "My iPhone", isScreen: true)
        let other = DemoSource(id: "tablet", name: "Another iPad", isScreen: true)
        let camera = DemoSource(id: "webcam", name: "External camera", isScreen: false)
        var state = CaptureRecovery()
        XCTAssertTrue(state.candidate(in: [camera]) == nil, "Never auto-open a webcam")
        XCTAssertTrue(state.candidate(in: [phone, other]) == nil, "Ambiguous devices require selection")
        XCTAssertEqual(state.candidate(in: [phone, camera]), "phone")
        let first = state.select(phone.id)
        XCTAssertTrue(state.candidate(in: [other, camera]) == nil, "Disconnect cannot switch to another person's device")
        XCTAssertEqual(state.candidate(in: [phone, other]), "phone")
        let retry = state.select(phone.id)
        XCTAssertFalse(state.accepts(first, source: phone.id), "Queued frames from the former session are stale")
        XCTAssertTrue(state.accepts(retry, source: phone.id))
        _ = state.select(nil)
        XCTAssertFalse(state.accepts(retry, source: phone.id), "End demo invalidates pending frames")
    }
    func testHandTransparencyPersistenceAndNoStretch() throws {
        let root = try temporary(); defer { try? FileManager.default.removeItem(at: root) }
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 100, pixelsHigh: 100, bitsPerSample: 8,
            samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        for y in 0..<100 { for x in 0..<100 { bitmap.setColor(NSColor(deviceRed: 1, green: 0.5, blue: 0.1, alpha: x > 40 && y > 40 ? 1 : 0), atX: x, y: y) } }
        let png = root.appendingPathComponent("hand.png"); try bitmap.representation(using: .png, properties: [:])!.write(to: png)
        let cutout = NSImage(contentsOf: png)!
        XCTAssertTrue(HandRenderer.hasTransparency(cutout))
        XCTAssertTrue(HandRenderer.hasTransparency(HandRenderer.toned(cutout, tone: .deeper)))
        let opaque = NSImage(size: CGSize(width: 100, height: 100), flipped: false) { rect in NSColor.gray.setFill(); rect.fill(); return true }
        XCTAssertFalse(HandRenderer.hasTransparency(opaque), "Baked white/checkerboard backgrounds are not alpha cutouts")
        var scene = DemoScene(background: "background.png"); scene.viewport = .phone
        let store = root.appendingPathComponent("store")
        try SceneStorage.save([scene], to: store.appendingPathComponent("scenes.json"))
        let model = DemoScenes(root: store); try model.addHand(png, to: scene.id)
        scene = model.selected!; scene.hand!.tone = .deeper; scene.hand!.mirrored = true; model.update(scene)
        try FileManager.default.removeItem(at: png)
        let reopened = DemoScenes(root: store)
        XCTAssertEqual(reopened.selected?.hand, scene.hand)
        XCTAssertNotNil(reopened.handImage(for: scene))
        for shape in [DeviceViewport.phone, .tablet, .landscape] {
            scene.viewport = shape
            let device = ViewportGeometry(scene: scene, size: CGSize(width: 1920, height: 1080)).outer
            let rect = HandRenderer.rect(scene.hand!, imageSize: CGSize(width: 600, height: 800), device: device)
            XCTAssertEqual(rect.width / rect.height, 0.75, accuracy: 0.00001)
        }
        var unsafe = SceneHand(image: "../secret.png")
        XCTAssertThrowsError(try unsafe.validated()); unsafe.image = "hand.png"; unsafe.scale = .nan
        XCTAssertThrowsError(try unsafe.validated())
    }
    func testLogoLibraryMigrationReuseAndRemoval() throws {
        let root = try temporary(); defer { try? FileManager.default.removeItem(at: root) }
        let data = try SceneLibraryStorage.textLogo("Sample Customer")
        let file = root.appendingPathComponent("existing.png"); try data.write(to: file)
        XCTAssertTrue(HandRenderer.hasTransparency(NSImage(contentsOf: file)!))
        var first = DemoScene(name: "Prior customer", background: "backdrop.png")
        first.logo = SceneLogo(image: "existing.png", corner: .bottomLeft, backing: .dark)
        var second = first; second.id = UUID(); second.name = "Second customer"
        try SceneStorage.save([first, second], to: root.appendingPathComponent("scenes.json"))
        let originalArchive = try Data(contentsOf: root.appendingPathComponent("scenes.json"))
        let model = DemoScenes(root: root)
        XCTAssertEqual(model.savedLogos.count, 1, "Previously imported logos are adopted once and deduplicated")
        XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent("scenes.json")), originalArchive)
        let saved = model.savedLogos[0]
        model.renameSavedLogo(saved.id, name: "Reusable customer")
        try model.addLogo(file, to: first.id)
        XCTAssertEqual(model.savedLogos.count, 1, "Reimporting identical artwork does not duplicate the library")
        model.selectedID = second.id; model.useSavedLogo(saved)
        XCTAssertEqual(model.selected?.logo?.corner, .bottomLeft)
        XCTAssertEqual(model.selected?.logo?.backing, .dark)
        XCTAssertEqual(DemoScenes(root: root).savedLogos.first?.name, "Reusable customer")
        model.removeSavedLogo(saved.id)
        let reopened = DemoScenes(root: root)
        XCTAssertTrue(reopened.savedLogos.isEmpty, "Removed logos must not be re-adopted on every launch")
        XCTAssertNotNil(reopened.logoImage(for: reopened.scenes[1]))
        XCTAssertTrue(FileManager.default.fileExists(atPath: file.path))
        reopened.makeTextLogo("Example Care")
        XCTAssertEqual(reopened.savedLogos.first?.name, "Example Care")
        XCTAssertNotNil(DemoScenes(root: root).selected?.logo)
        XCTAssertThrowsError(try SceneLibraryStorage.textLogo("  "))
        XCTAssertThrowsError(try SavedSceneLogo(name: "Unsafe", image: "../outside.png").validated())
    }
    func testLibraryCustomizationAndCorruptFileSafety() throws {
        let root = try temporary(); defer { try? FileManager.default.removeItem(at: root) }
        let a = DemoScene(name: "Customer A", background: "a.png")
        let b = DemoScene(name: "Customer B", background: "b.png")
        try SceneStorage.save([a, b], to: root.appendingPathComponent("scenes.json"))
        let model = DemoScenes(root: root)
        let first = model.starters[0].id, second = model.starters[1].id
        model.customizeStarter { $0.names[first] = "My reception"; $0.move(first, by: 1); $0.hidden.insert(second) }
        let reopened = DemoScenes(root: root)
        XCTAssertEqual(reopened.starters.first?.id, first)
        XCTAssertEqual(reopened.starters.first?.name, "My reception")
        XCTAssertEqual(reopened.starters.count, SceneStarters.all.count - 1)
        XCTAssertEqual(reopened.scenes.map(\.id), [a.id, b.id], "Gallery organization cannot rewrite customer scenes")
        reopened.moveScene(b.id, by: -1)
        XCTAssertEqual(DemoScenes(root: root).scenes.map(\.id), [b.id, a.id])
        reopened.customizeStarter { $0 = StarterPreferences() }
        XCTAssertEqual(DemoScenes(root: root).starters.map(\.id), SceneStarters.all.map(\.id))
        let broken = Data("{not-readable".utf8)
        for name in ["saved-logos.json", "starter-preferences.json"] { try broken.write(to: root.appendingPathComponent(name)) }
        let protected = DemoScenes(root: root)
        protected.customizeStarter { $0.hidden.insert(first) }
        protected.removeSavedLogo(UUID())
        protected.makeTextLogo("Still works in this scene")
        XCTAssertNotNil(protected.selected?.logo)
        for name in ["saved-logos.json", "starter-preferences.json"] {
            XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent(name)), broken, "Unreadable user data is preserved")
        }
        let duplicate = SavedSceneLogo(name: "Duplicate", image: "fixture.png")
        let duplicateData = try JSONEncoder().encode([duplicate, duplicate])
        try duplicateData.write(to: root.appendingPathComponent("saved-logos.json"))
        let invalid = DemoScenes(root: root)
        XCTAssertTrue(invalid.savedLogos.isEmpty, "Invalid duplicate identifiers cannot reach the SwiftUI list")
        invalid.removeSavedLogo(duplicate.id)
        XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent("saved-logos.json")), duplicateData)
        var preferences = StarterPreferences()
        preferences.order = [first, first, "obsolete"]
        XCTAssertEqual(Set(preferences.visible.map(\.id)).count, SceneStarters.all.count)
    }
}
