import AppKit

final class SceneTests {
    func testDesktopVerificationWaitsForMacOSAndStopsAtTimeout() throws {
        let original = URL(fileURLWithPath: "/original.jpg")
        let expected = URL(fileURLWithPath: "/scene.png")
        let manual = URL(fileURLWithPath: "/user-chosen.jpg")
        var current: URL? = original
        var scheduled: [() -> Void] = []
        var results: [Bool] = []
        var reads = 0
        DesktopImageVerification.confirm(expected, read: { reads += 1; return current }, attempts: 3,
            schedule: { scheduled.append($0) }, completion: { results.append($0) })
        XCTAssertTrue(results.isEmpty, "A stale immediate read must leave verification pending")
        XCTAssertEqual(reads, 1)
        XCTAssertEqual(scheduled.count, 1)
        scheduled.removeFirst()()
        XCTAssertTrue(results.isEmpty, "macOS can return the earlier picture more than once")
        current = expected
        scheduled.removeFirst()()
        XCTAssertEqual(results, [true])
        XCTAssertEqual(reads, 3)
        XCTAssertTrue(scheduled.isEmpty, "Successful verification must stop polling")

        current = manual; results = []; reads = 0
        DesktopImageVerification.confirm(expected, read: { reads += 1; return current }, attempts: 2,
            schedule: { scheduled.append($0) }, completion: { results.append($0) })
        while !scheduled.isEmpty { scheduled.removeFirst()() }
        XCTAssertEqual(results, [false], "An unconfirmed or manual picture change must not report success")
        XCTAssertEqual(reads, 3, "Verification must have a finite retry bound")
        XCTAssertEqual(current, manual, "Verification must not overwrite a later manual change")
        XCTAssertFalse(DesktopImageVerification.matches(nil, expected))

        let root = try temporary(); defer { try? FileManager.default.removeItem(at: root) }
        let image = root.appendingPathComponent("original.heic")
        let alias = root.appendingPathComponent("alias.heic")
        try Data("image fixture".utf8).write(to: image)
        try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: image)
        XCTAssertTrue(DesktopImageVerification.matches(alias, image), "Equivalent file URLs should confirm without changing the saved original URL")
        let snapshot = DesktopSnapshot(screenID: "display", originalURL: alias, appliedURL: image)
        XCTAssertTrue(snapshot.owns(alias))
        XCTAssertEqual(snapshot.originalURL, alias)
    }
    func testSceneSearchSelectsOnlyMatchingCustomers() throws {
        let root = try temporary(); defer { try? FileManager.default.removeItem(at: root) }
        let first = DemoScene(name: "Customer A reception", background: "a.png")
        let second = DemoScene(name: "Customer B workshop", background: "b.png")
        try SceneStorage.save([first, second], to: root.appendingPathComponent("scenes.json"))
        let model = DemoScenes(root: root)
        XCTAssertEqual(model.selected?.id, first.id)
        model.query = "workshop"
        XCTAssertEqual(model.selectedID, second.id)
        XCTAssertEqual(model.selected?.id, second.id)
        model.query = "no such customer"
        XCTAssertTrue(model.matches.isEmpty)
        XCTAssertTrue(model.selectedID == nil)
        XCTAssertTrue(model.selected == nil, "An unmatched previous backdrop must not remain ready to apply")
        model.query = "reception"
        model.remove()
        XCTAssertTrue(model.selected == nil, "Removing the sole match must not select a different customer")
        XCTAssertEqual(model.scenes.count, 1)
        model.query = ""
        XCTAssertEqual(model.selected?.id, second.id)
    }
    func testDesktopRecoverySurvivesInterruptedSwitch() throws {
        let original = URL(fileURLWithPath: "/original.jpg")
        let first = URL(fileURLWithPath: "/scene-a.png")
        let second = URL(fileURLWithPath: "/scene-b.png")
        let journal = DesktopSnapshot(screenID: "display", originalURL: original, appliedURL: first,
                                      pendingURL: second, scaling: nil, clipping: nil, fill: nil)
        let recovered = try JSONDecoder().decode(DesktopSnapshot.self, from: JSONEncoder().encode(journal))
        XCTAssertTrue(recovered.owns(first), "Failed switch must retain recovery of the earlier scene")
        XCTAssertTrue(recovered.owns(second), "Interrupted finalization must still restore the new scene")
        XCTAssertFalse(recovered.owns(original), "Manual wallpaper changes must not be overwritten")
        XCTAssertFalse(recovered.owns(nil))
        XCTAssertEqual(recovered.originalURL, original)

        // B reached the desktop, but its final journal write was interrupted.
        // Retrying with C must still recover B if C never reaches the desktop.
        let third = URL(fileURLWithPath: "/scene-c.png")
        let retry = recovered.preparingSwitch(to: third, current: second)!
        let retried = try JSONDecoder().decode(DesktopSnapshot.self, from: JSONEncoder().encode(retry))
        XCTAssertTrue(retried.owns(second), "A failed retry must retain the picture actually on screen")
        XCTAssertTrue(retried.owns(third), "An interrupted retry finalization must recognize its new picture")
        XCTAssertFalse(retried.owns(first), "The obsolete picture must not replace the observed desktop")
        XCTAssertEqual(retried.originalURL, original)
        XCTAssertEqual(retried.appliedURL, second)
        XCTAssertTrue(recovered.preparingSwitch(to: third, current: original) == nil)
        XCTAssertTrue(recovered.preparingSwitch(to: third, current: nil) == nil)
    }
    private func temporary() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("StageMarkSceneTests-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
    func testSceneRoundTripAndBounds() throws {
        let root = try temporary(); defer { try? FileManager.default.removeItem(at: root) }
        var scene = DemoScene(name: "Reception", background: "photo.png")
        scene.phoneX = 3; scene.phoneHeight = -1; scene.zoom = 9
        try SceneStorage.save([scene], to: root.appendingPathComponent("scenes.json"))
        let saved = try SceneStorage.load(root.appendingPathComponent("scenes.json"))
        XCTAssertEqual(saved.count, 1); XCTAssertEqual(saved[0].id, scene.id)
        XCTAssertEqual(saved[0].phoneX, 1); XCTAssertEqual(saved[0].phoneHeight, 0.3); XCTAssertEqual(saved[0].zoom, 3)
    }
    func testUnsafeImagePathsAndNumbersRejected() throws {
        for filename in ["../private.png", "/tmp/image.png", "folder/file.png", "folder\\file.png", ".hidden", ""] {
            XCTAssertThrowsError(try DemoScene(background: filename).validated())
        }
        var scene = DemoScene(background: "valid.png"); scene.phoneX = .infinity
        XCTAssertThrowsError(try scene.validated())
        scene.phoneX = 0.5; scene.name = "   "
        XCTAssertThrowsError(try scene.validated())
    }
    func testCorruptAndFutureArchivesPreserved() throws {
        let root = try temporary(); defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("scenes.json")
        for payload in [Data("broken".utf8), Data("{\"version\":9,\"scenes\":[]}".utf8)] {
            try payload.write(to: url)
            let model = DemoScenes(root: root)
            XCTAssertTrue(model.storageBlocked)
            XCTAssertNotNil(model.notice)
            model.update(DemoScene(background: "image.png"))
            XCTAssertEqual(try Data(contentsOf: url), payload)
        }
    }
    func testDuplicateIDsRejected() throws {
        let root = try temporary(); defer { try? FileManager.default.removeItem(at: root) }
        let scene = DemoScene(background: "photo.png")
        let url = root.appendingPathComponent("scenes.json")
        try JSONEncoder().encode(SceneArchive(scenes: [scene, scene])).write(to: url)
        XCTAssertThrowsError(try SceneStorage.load(url))
    }
    func testPhoneStaysWithinWideAndTallDisplays() throws {
        for size in [CGSize(width: 1920, height: 1080), CGSize(width: 1080, height: 1920), CGSize(width: 3440, height: 1440)] {
            for x in [0.0, 0.5, 1.0] {
                var scene = DemoScene(background: "photo.png"); scene.phoneX = x; scene.phoneY = x; scene.phoneHeight = 0.96
                let frame = SceneRenderer.phoneRect(scene, in: size)
                XCTAssertTrue(CGRect(origin: .zero, size: size).contains(frame))
                XCTAssertGreaterThan(frame.width, 0)
            }
        }
    }
    func testRenderAndImportedImageSurviveSourceRemoval() throws {
        let root = try temporary(); defer { try? FileManager.default.removeItem(at: root) }
        let image = NSImage(size: CGSize(width: 80, height: 45), flipped: false) { rect in
            NSColor.red.setFill(); rect.fill(); return true
        }
        let scene = DemoScene(background: "source.png")
        let data = try SceneRenderer.png(scene, image: image, size: CGSize(width: 800, height: 450))
        let bitmap = NSBitmapImageRep(data: data)!
        XCTAssertEqual(bitmap.pixelsWide, 800); XCTAssertEqual(bitmap.pixelsHigh, 450)
        XCTAssertGreaterThan(bitmap.colorAt(x: 5, y: 5)!.redComponent, 0.9)
        let source = root.appendingPathComponent("source.png"); try data.write(to: source)
        let modelRoot = root.appendingPathComponent("store")
        let model = DemoScenes(root: modelRoot)
        try model.addImage(source, name: "Demo reception")
        let imported = model.selected!
        try FileManager.default.removeItem(at: source)
        let reloaded = DemoScenes(root: modelRoot)
        XCTAssertEqual(reloaded.scenes.first?.name, "Demo reception")
        XCTAssertNotNil(reloaded.image(for: imported))
        reloaded.duplicate()
        XCTAssertEqual(reloaded.scenes.count, 2)
        XCTAssertEqual(reloaded.scenes[0].background, reloaded.scenes[1].background)
        reloaded.remove()
        XCTAssertNotNil(reloaded.image(for: imported))
    }
}
