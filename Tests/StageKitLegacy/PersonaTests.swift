import AppKit
import ImageIO
import UniformTypeIdentifiers

final class PersonaTests {
    private func temporary() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("PersonaTests-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }
    private func fixture() throws -> Data {
        let context = CGContext(data: nil, width: 40, height: 80, bitsPerComponent: 8, bytesPerRow: 160,
                                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(CGColor(red: 0, green: 0, blue: 1, alpha: 1)); context.fill(CGRect(x: 0, y: 0, width: 40, height: 80))
        context.clear(CGRect(x: 15, y: 30, width: 10, height: 20))
        let data = NSMutableData()
        let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(destination, context.makeImage()!, nil)
        guard CGImageDestinationFinalize(destination) else { throw PersonaError.unreadableImage }
        return data as Data
    }

    func testGeometryBoundsAndValidation() throws {
        for image in [CGSize(width: 300, height: 100), CGSize(width: 100, height: 800), CGSize(width: 1, height: 1)] {
            for canvas in [CGSize(width: 1920, height: 1080), CGSize(width: 800, height: 1600), CGSize(width: 1, height: 1)] {
                for x in [0.0, 0.5, 1.0] {
                    for y in [0.0, 0.5, 1.0] {
                        let placement = PersonaPlacement(image: "persona.png", x: x, y: y, width: 0.4)
                        let rect = PersonaGeometry.rect(placement, imageSize: image, in: canvas)
                        XCTAssertTrue(rect.minX >= 0 && rect.minY >= 0 && rect.maxX <= canvas.width + 1e-8 && rect.maxY <= canvas.height + 1e-8)
                        XCTAssertTrue(rect.width <= canvas.width * 0.4 + 1e-8 && rect.height <= canvas.height * 0.6 + 1e-8)
                        XCTAssertEqual(rect.width / rect.height, image.width / image.height, accuracy: 1e-8)
                        if y == 1 { XCTAssertEqual(rect.maxY, canvas.height, accuracy: 1e-8) }
                    }
                }
            }
        }
        for path in ["../persona.png", "/persona.png", "folder\\persona.png", ".hidden.png", "persona.svg", "", "bad\0.png"] {
            XCTAssertThrowsError(try PersonaPlacement(image: path).validated())
        }
        XCTAssertThrowsError(try PersonaPlacement(image: "persona.png", x: .nan).validated())
        let clamped = try PersonaPlacement(image: "persona.png", x: -2, y: 8, width: 3).validated()
        XCTAssertEqual(clamped.x, 0); XCTAssertEqual(clamped.y, 1); XCTAssertEqual(clamped.width, 0.4)
        XCTAssertEqual(PersonaGeometry.rect(clamped, imageSize: .zero, in: CGSize(width: 100, height: 100)), .zero)
        let defensive = PersonaGeometry.rect(PersonaPlacement(image: "persona.png", x: .nan, y: .infinity, width: .nan),
                                             imageSize: CGSize(width: 300, height: 100), in: CGSize(width: 800, height: 600))
        XCTAssertTrue([defensive.minX, defensive.minY, defensive.width, defensive.height].allSatisfy(\.isFinite))
    }

    func testDurableImportSeparatePlacementAndRemoval() throws {
        let root = try temporary(); defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("Operations leader.png"); try fixture().write(to: source)
        let store = root.appendingPathComponent("store")
        let library = PersonaLibrary(root: store)
        let item = try library.addImage(source)
        XCTAssertEqual(library.items, [item]); XCTAssertEqual(library.selectedID, item.id)
        XCTAssertTrue(item.image.hasPrefix("persona-") && item.image.hasSuffix(".png"))
        XCTAssertFalse(library.overlayVisible)
        library.setOverlayWidth(0.32); library.setOverlayLocked(true)
        library.setOverlayPosition(x: 0.02, y: 0.98)
        let scenePlacement = PersonaPlacement(image: item.image, x: 0.1, y: 0.9, width: 0.12)
        try FileManager.default.removeItem(at: source)
        let reopened = PersonaLibrary(root: store)
        XCTAssertFalse(reopened.overlayVisible, "A persisted card must never reopen over another app on launch")
        XCTAssertTrue(reopened.overlayLocked); XCTAssertEqual(reopened.overlayWidth, 0.32)
        let savedPosition = try JSONDecoder().decode(PersonaOverlayState.self, from: Data(contentsOf: store.appendingPathComponent("persona-overlay.json")))
        XCTAssertEqual(savedPosition.x, 0.02); XCTAssertEqual(savedPosition.y, 0.98)
        XCTAssertEqual(scenePlacement.width, 0.12)
        XCTAssertNotNil(reopened.image(named: item.image))
        let image = reopened.image(named: item.image)!
        let bitmap = NSBitmapImageRep(data: image.tiffRepresentation!)!
        XCTAssertEqual(Double(bitmap.colorAt(x: 20, y: 40)!.alphaComponent), 0, accuracy: 0.001)
        reopened.rename(item.id, name: "Edited persona")
        XCTAssertEqual(reopened.selected?.name, "Edited persona")
        reopened.remove(item.id)
        XCTAssertTrue(reopened.items.isEmpty)
        XCTAssertTrue(reopened.image(named: item.image) != nil, "Scenes can still reference removed library entries")
        XCTAssertTrue(FileManager.default.fileExists(atPath: store.appendingPathComponent(item.image).path))
        XCTAssertTrue(reopened.image(named: "../Operations leader.png") == nil)
    }

    func testCorruptFutureAndConcurrentArchivesStayUntouched() throws {
        let root = try temporary(); defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("persona.png"); try fixture().write(to: source)
        let item = SavedPersona(name: "Saved", image: "persona.png")
        let invalidArchives = [Data("not json".utf8),
            try JSONEncoder().encode(PersonaArchive(version: 2, items: [], selectedID: nil)),
            try JSONEncoder().encode(PersonaArchive(items: [item, item], selectedID: item.id)),
            try JSONEncoder().encode(PersonaArchive(items: [item], selectedID: UUID()))]
        for invalid in invalidArchives {
            let store = root.appendingPathComponent(UUID().uuidString)
            try FileManager.default.createDirectory(at: store, withIntermediateDirectories: true)
            let archive = store.appendingPathComponent("persona-library.json"); try invalid.write(to: archive)
            let library = PersonaLibrary(root: store)
            XCTAssertTrue(library.isReadOnly); XCTAssertThrowsError(try library.addImage(source))
            library.remove(item.id); library.rename(item.id, name: "Changed")
            XCTAssertEqual(try Data(contentsOf: archive), invalid)
            XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: store.path), ["persona-library.json"])
        }
        let store = root.appendingPathComponent("changed")
        let library = PersonaLibrary(root: store); _ = try library.addImage(source)
        let archive = store.appendingPathComponent("persona-library.json")
        let invalid = Data("external edit".utf8); try invalid.write(to: archive)
        let before = try FileManager.default.contentsOfDirectory(atPath: store.path).sorted()
        XCTAssertThrowsError(try library.addImage(source))
        XCTAssertEqual(try Data(contentsOf: archive), invalid)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: store.path).sorted(), before, "A failed commit must remove only its new unreferenced PNG")
        let overlay = store.appendingPathComponent("persona-overlay.json"); try invalid.write(to: overlay)
        let blocked = PersonaLibrary(root: store)
        blocked.setOverlayWidth(0.25)
        XCTAssertEqual(try Data(contentsOf: overlay), invalid)

        let linkedStore = root.appendingPathComponent("linked")
        try FileManager.default.createDirectory(at: linkedStore, withIntermediateDirectories: true)
        let link = linkedStore.appendingPathComponent("persona-library.json")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: root.appendingPathComponent("absent-target"))
        let linked = PersonaLibrary(root: linkedStore)
        XCTAssertTrue(linked.isReadOnly); XCTAssertThrowsError(try linked.addImage(source))
        XCTAssertEqual(try FileManager.default.destinationOfSymbolicLink(atPath: link.path), root.appendingPathComponent("absent-target").path)
    }

    func testSceneAttachmentTransparencyAndMissingFile() throws {
        let root = try temporary(); defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("persona.png"); try fixture().write(to: source)
        let model = DemoScenes(root: root.appendingPathComponent("store"))
        try model.addImage(source, name: "First scene"); let firstID = model.selected!.id
        try model.addImage(source, name: "Second scene"); let secondID = model.selected!.id
        let persona = try model.personas.addImage(source)
        model.usePersona(persona, in: firstID)
        XCTAssertNotNil(model.scenes.first { $0.id == firstID }?.persona)
        XCTAssertTrue(model.scenes.first { $0.id == secondID }?.persona == nil, "A chooser must attach to its captured scene ID")
        var scene = model.scenes.first { $0.id == firstID }!
        scene.showsPhone = false; scene.persona = PersonaPlacement(image: persona.image, x: 0.5, y: 0.5, width: 0.4)
        model.update(scene)
        let roundTrip = DemoScenes(root: model.root)
        XCTAssertEqual(roundTrip.scenes.first { $0.id == firstID }?.persona, scene.persona)
        model.personas.remove(persona.id)
        XCTAssertNotNil(model.personaImage(for: scene))
        let background = NSImage(size: CGSize(width: 300, height: 200), flipped: false) { rect in NSColor.red.setFill(); rect.fill(); return true }
        let output = try model.renderPNG(scene, image: background, size: CGSize(width: 300, height: 200))
        let bitmap = NSBitmapImageRep(data: output)!
        let center = bitmap.colorAt(x: 150, y: 100)!.usingColorSpace(.deviceRGB)!
        XCTAssertGreaterThan(center.redComponent, 0.95, "The persona's transparent hole must show the scene below")
        let edge = bitmap.colorAt(x: 130, y: 100)!.usingColorSpace(.deviceRGB)!
        XCTAssertGreaterThan(edge.blueComponent, 0.95, "The saved persona must be included in the exported scene")
        try FileManager.default.removeItem(at: model.root.appendingPathComponent(persona.image))
        XCTAssertTrue(model.personaImage(for: scene) == nil)
        XCTAssertThrowsError(try model.renderPNG(scene, image: background, size: CGSize(width: 300, height: 200)))
        let legacy = try JSONEncoder().encode(DemoScene(background: "old.png"))
        XCTAssertTrue(try JSONDecoder().decode(DemoScene.self, from: legacy).persona == nil)
    }

    func testNativeOverlayWindowAndDragLifecycle() throws {
        let controller = PersonaOverlayController()
        defer { controller.shutdown() }
        guard let window = controller.window, let artwork = window.contentView,
              let screen = NSScreen.main ?? NSScreen.screens.first,
              let image = NSImage(data: try fixture()) else {
            XCTAssertTrue(false, "The native overlay test needs a display and its synthetic image")
            return
        }
        let frontmost = NSWorkspace.shared.frontmostApplication?.processIdentifier
        let previousKeyWindow = NSApp.keyWindow
        let displayID = (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
        var state = PersonaOverlayState(x: 0.5, y: 0.5, width: 0.10, screenID: displayID)
        var placements: [PersonaOverlayState] = []
        controller.onPlacementChange = { placements.append($0) }
        func event(_ type: NSEvent.EventType, at point: CGPoint) -> NSEvent {
            // Deliver only to this synthetic panel. Nothing is posted to the
            // system event queue, so other apps never receive mouse input.
            NSEvent.mouseEvent(with: type, location: window.convertPoint(fromScreen: point),
                               modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                               windowNumber: window.windowNumber, context: nil,
                               eventNumber: 0, clickCount: 1, pressure: 1)!
        }
        func isOnScreen(_ frame: CGRect) -> Bool {
            NSScreen.screens.contains { $0.visibleFrame.insetBy(dx: -1, dy: -1).contains(frame) }
        }

        XCTAssertFalse(window.isVisible)
        XCTAssertFalse(window.canBecomeKey); XCTAssertFalse(window.canBecomeMain)
        XCTAssertTrue(window.styleMask.contains(.nonactivatingPanel))
        XCTAssertFalse(window.isOpaque); XCTAssertFalse(window.hasShadow)
        XCTAssertEqual(window.level, .floating)
        controller.configure(image: image, name: "Synthetic persona test", state: state)
        XCTAssertFalse(window.isVisible, "Configuring or resizing must not show a hidden persona")
        XCTAssertFalse(window.ignoresMouseEvents)
        XCTAssertTrue(isOnScreen(window.frame))
        let shown = controller.show(image: image, name: "Synthetic persona test", state: state)
        XCTAssertTrue(window.isVisible)
        XCTAssertFalse(window.isKeyWindow); XCTAssertFalse(window.isMainWindow)
        XCTAssertNotNil(shown.screenID)
        XCTAssertTrue(isOnScreen(window.frame))
        XCTAssertTrue(NSApp.keyWindow === previousKeyWindow, "Showing the persona must preserve the existing key window")
        XCTAssertEqual(NSWorkspace.shared.frontmostApplication?.processIdentifier, frontmost,
                       "Showing a nonactivating persona must preserve the foreground application")

        let start = window.frame
        let anchor = CGPoint(x: start.midX, y: start.midY)
        let first = CGPoint(x: anchor.x + 18, y: anchor.y + 12)
        let second = CGPoint(x: anchor.x + 36, y: anchor.y + 24)
        let down = event(.leftMouseDown, at: anchor)
        XCTAssertTrue(artwork.acceptsFirstMouse(for: down))
        artwork.mouseDown(with: down)
        artwork.mouseDragged(with: event(.leftMouseDragged, at: first))
        artwork.mouseDragged(with: event(.leftMouseDragged, at: second))
        artwork.mouseUp(with: event(.leftMouseUp, at: second))
        XCTAssertEqual(placements.count, 1)
        XCTAssertEqual(window.frame.minX, start.minX + 36, accuracy: 1)
        XCTAssertEqual(window.frame.minY, start.minY + 24, accuracy: 1)
        XCTAssertTrue(isOnScreen(window.frame))
        guard let dragged = placements.last else { return }
        XCTAssertGreaterThan(dragged.x, state.x); XCTAssertGreaterThan(dragged.y, state.y)

        state = dragged; state.locked = true
        controller.configure(image: image, name: "Synthetic persona test", state: state)
        let lockedFrame = window.frame
        XCTAssertTrue(window.ignoresMouseEvents)
        artwork.mouseDown(with: event(.leftMouseDown, at: CGPoint(x: lockedFrame.midX, y: lockedFrame.midY)))
        artwork.mouseDragged(with: event(.leftMouseDragged, at: CGPoint(x: lockedFrame.midX + 60, y: lockedFrame.midY + 40)))
        artwork.mouseUp(with: event(.leftMouseUp, at: CGPoint(x: lockedFrame.midX + 60, y: lockedFrame.midY + 40)))
        XCTAssertEqual(window.frame, lockedFrame, "Locked artwork must ignore even directly delivered drag events")
        XCTAssertEqual(placements.count, 1)

        state.locked = false
        controller.configure(image: image, name: "Synthetic persona test", state: state)
        XCTAssertFalse(window.ignoresMouseEvents)
        let edgeAnchor = CGPoint(x: window.frame.midX, y: window.frame.midY)
        let outside = CGPoint(x: screen.visibleFrame.maxX + 500, y: screen.visibleFrame.maxY + 500)
        artwork.mouseDown(with: event(.leftMouseDown, at: edgeAnchor))
        artwork.mouseDragged(with: event(.leftMouseDragged, at: outside))
        artwork.mouseUp(with: event(.leftMouseUp, at: outside))
        XCTAssertEqual(placements.count, 2)
        XCTAssertTrue(isOnScreen(window.frame), "Ending an off-screen drag must clamp the card to an available display")
        XCTAssertTrue(placements.allSatisfy { (0...1).contains($0.x) && (0...1).contains($0.y) })
        XCTAssertFalse(window.isKeyWindow); XCTAssertFalse(window.isMainWindow)
        XCTAssertEqual(NSWorkspace.shared.frontmostApplication?.processIdentifier, frontmost)
        controller.hide(); XCTAssertFalse(window.isVisible)
        controller.configure(image: image, name: "Synthetic persona test", state: state)
        XCTAssertFalse(window.isVisible)
        controller.shutdown(); XCTAssertFalse(window.isVisible)
        XCTAssertTrue(controller.onPlacementChange == nil)
    }
}
