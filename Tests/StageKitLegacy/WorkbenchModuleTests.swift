import AppKit
import Carbon

final class WorkbenchModuleTests: XCTestCase {
    func testMigrationCopiesPreviewOnceAndPreservesMalformedFiles() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("WorkbenchMigration-" + UUID().uuidString)
        let suite = "WorkbenchMigrationTests." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { try? FileManager.default.removeItem(at: root); defaults.removePersistentDomain(forName: suite) }
        let source = root.appendingPathComponent("StageMark Preview")
        let production = root.appendingPathComponent("StageMark")
        try FileManager.default.createDirectory(at: source.appendingPathComponent("Scenes"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: production, withIntermediateDirectories: true)
        let malformed = Data("preserve this malformed archive".utf8)
        try malformed.write(to: source.appendingPathComponent("boards.json"))
        try malformed.write(to: source.appendingPathComponent("Scenes/scenes.json"))
        try Data("old Space recovery".utf8).write(to: source.appendingPathComponent("Scenes/desktop-restore.json"))
        try Data("production must not win".utf8).write(to: production.appendingPathComponent("boards.json"))
        let notice = Workbench.prepareStageData(applicationSupport: root, defaults: defaults, preview: true)
        XCTAssertTrue(notice == nil)
        let destination = root.appendingPathComponent("Workbench Preview/StageMark")
        XCTAssertEqual(try Data(contentsOf: destination.appendingPathComponent("boards.json")), malformed)
        XCTAssertEqual(try Data(contentsOf: destination.appendingPathComponent("Scenes/scenes.json")), malformed)
        XCTAssertFalse(FileManager.default.fileExists(atPath: destination.appendingPathComponent("Scenes/desktop-restore.json").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: source.appendingPathComponent("Scenes/desktop-restore.json").path))
        XCTAssertThrowsError(try BoardStorage.load(from: destination.appendingPathComponent("boards.json")))
        let scenes = DemoScenes(root: destination.appendingPathComponent("Scenes"))
        XCTAssertTrue(scenes.storageBlocked)
        XCTAssertEqual(try Data(contentsOf: destination.appendingPathComponent("Scenes/scenes.json")), malformed)
        let newData = Data("my new preview board".utf8)
        try newData.write(to: destination.appendingPathComponent("boards.json"))
        XCTAssertTrue(Workbench.prepareStageData(applicationSupport: root, defaults: defaults, preview: true) == nil)
        XCTAssertEqual(try Data(contentsOf: destination.appendingPathComponent("boards.json")), newData)
        XCTAssertEqual(try Data(contentsOf: source.appendingPathComponent("boards.json")), malformed)
    }

    func testMigrationRejectsSymlinksAndRetriesCleanly() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("WorkbenchMigrationLinks-" + UUID().uuidString)
        let suite = "WorkbenchMigrationTests." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { try? FileManager.default.removeItem(at: root); defaults.removePersistentDomain(forName: suite) }
        let source = root.appendingPathComponent("StageMark")
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        let elsewhere = root.appendingPathComponent("outside.json")
        let bytes = Data("unrelated original".utf8)
        try bytes.write(to: elsewhere)
        try FileManager.default.createSymbolicLink(at: source.appendingPathComponent("boards.json"), withDestinationURL: elsewhere)
        XCTAssertTrue(Workbench.prepareStageData(applicationSupport: root, defaults: defaults, preview: true) != nil)
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("Workbench Preview/StageMark").path))
        XCTAssertEqual(try Data(contentsOf: elsewhere), bytes)
        try FileManager.default.removeItem(at: source.appendingPathComponent("boards.json"))
        try BoardStorage.save(BoardArchive(), to: source.appendingPathComponent("boards.json"))
        XCTAssertTrue(Workbench.prepareStageData(applicationSupport: root, defaults: defaults, preview: true) == nil)
        XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent("Workbench Preview/StageMark/boards.json").path))
    }

    func testEmbeddedCallbacksAndSuspendedShortcutSettings() throws {
        let suite = "WorkbenchEmbeddedTests." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(suite)
        defer { defaults.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: root) }
        let settings = SettingsStore(defaults: defaults)
        for action in Action.allCases { var shortcut = action.defaultShortcut; shortcut.enabled = false; settings.value.shortcuts[action.rawValue] = shortcut }
        let app = AppCoordinator(settings: settings, archiveURL: root.appendingPathComponent("boards.json"), embedded: true)
        app.demoScenes = DemoScenes(root: root.appendingPathComponent("Scenes"))
        var controls = 0, scenes = 0, keyboard = 0
        app.onOpenControls = { controls += 1 }
        app.onOpenScenes = { scenes += 1 }
        app.onOpenShortcuts = { keyboard += 1 }
        app.start()
        defer { app.shutdown() }
        XCTAssertFalse(app.hasPersistentMenuItem)
        app.showQuickControls(); app.showDemoScenes(); app.beginRecording(.pen)
        XCTAssertEqual(controls, 1); XCTAssertEqual(scenes, 1); XCTAssertEqual(keyboard, 1)
        XCTAssertTrue(app.recordingAction == nil)
        app.setShortcutsSuspended(true)
        settings.value.shortcuts[Action.pen.rawValue] = Shortcut(keyCode: UInt32(kVK_F18), modifiers: UInt32(controlKey | optionKey | shiftKey))
        let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [.control, .option, .shift], timestamp: 0,
            windowNumber: 0, context: nil, characters: "", charactersIgnoringModifiers: "", isARepeat: false, keyCode: UInt16(kVK_F18))!
        XCTAssertNotNil(app.hotkeys.handleLocalEvent(event))
        XCTAssertFalse(app.isDrawing)
        app.mayBeginInteraction = { false }
        app.startDrawing(.pen, latched: true)
        XCTAssertFalse(app.isDrawing)
        app.setShortcutsSuspended(false)
        XCTAssertTrue(app.shortcutFailures[.pen] == nil)
        XCTAssertTrue(app.hotkeys.handleLocalEvent(event) == nil)
        XCTAssertFalse(app.isDrawing)
    }
}
