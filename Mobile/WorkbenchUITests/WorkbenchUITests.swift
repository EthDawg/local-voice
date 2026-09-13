import XCTest

@MainActor
final class WorkbenchUITests: XCTestCase {
    private let sentence = "Meet at 3pm. Bring the revised drawings."

    private func launchIsolatedApp() -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        // Debug app code chooses a new temporary library for every launch.
        // This never resets, replaces or imports the installed user's library.
        app.launchArguments = ["--ui-testing"]
        app.launch()
        XCTAssertTrue(app.buttons["tool.dictate"].waitForExistence(timeout: 10))
        return app
    }

    private func reveal(_ element: XCUIElement, in app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        for _ in 0..<6 {
            if element.exists && element.isHittable { return }
            let scroll = app.scrollViews.firstMatch
            if scroll.exists {
                // Scroll through the outside margin, away from PencilKit ink,
                // image crop gestures and editable text in the content area.
                let start = scroll.coordinate(withNormalizedOffset: CGVector(dx: 0.98, dy: 0.8))
                let end = scroll.coordinate(withNormalizedOffset: CGVector(dx: 0.98, dy: 0.2))
                start.press(forDuration: 0.01, thenDragTo: end)
            } else { app.swipeUp() }
        }
        XCTAssertTrue(element.isHittable, "The control must be reachable by scrolling", file: file, line: line)
    }

    private func selectTab(_ label: String, in app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        let exactLabel = NSPredicate(format: "label == %@", label)
        let matches = app.descendants(matching: .any).matching(exactLabel)
        XCTAssertTrue(matches.firstMatch.waitForExistence(timeout: 5), "The \(label) tab must be available", file: file, line: line)
        // iPhone exposes tab buttons; the native iPad floating tab strip can
        // expose cells/other elements. Match the same exact accessible label.
        let queries = [app.buttons.matching(exactLabel), app.cells.matching(exactLabel), app.otherElements.matching(exactLabel)]
        for query in queries {
            if let target = query.allElementsBoundByIndex.first(where: { $0.isHittable }) {
                target.tap()
                let title = label == "Tools" ? "Workbench" : "Saved"
                XCTAssertTrue(app.navigationBars[title].waitForExistence(timeout: 5), file: file, line: line)
                return
            }
        }
        XCTFail("No actionable tab has the exact label \(label)", file: file, line: line)
    }

    private func attachScreenshot(_ name: String, of app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testTypedDraftCanBeSavedReopenedAndHandedToReading() {
        let app = launchIsolatedApp()
        app.buttons["tool.dictate"].tap()
        let draft = app.textViews["dictate.draft"]
        XCTAssertTrue(draft.waitForExistence(timeout: 5))
        reveal(draft, in: app)
        draft.tap()
        draft.typeText(sentence)
        XCTAssertEqual(draft.value as? String, sentence)
        let done = app.buttons["Done"]
        if done.exists && done.isHittable { done.tap() }
        let save = app.buttons["dictate.save"]
        reveal(save, in: app)
        save.tap()
        let notice = app.staticTexts["dictate.notice"]
        XCTAssertTrue(notice.waitForExistence(timeout: 5))
        XCTAssertEqual(notice.label, "Saved on this device.")

        app.navigationBars.buttons.firstMatch.tap()
        selectTab("Saved", in: app)
        let savedTitle = app.staticTexts[sentence].firstMatch
        XCTAssertTrue(savedTitle.waitForExistence(timeout: 5))
        savedTitle.tap()
        let savedText = app.textViews["Saved text"]
        XCTAssertTrue(savedText.waitForExistence(timeout: 5))
        XCTAssertEqual(savedText.value as? String, sentence)
        let read = app.buttons["Read aloud"]
        reveal(read, in: app)
        read.tap()
        let readingText = app.textViews["reading.text"]
        XCTAssertTrue(readingText.waitForExistence(timeout: 5))
        XCTAssertEqual(readingText.value as? String, sentence)
        XCTAssertTrue(app.buttons["reading.play"].isEnabled)
        attachScreenshot("Saved text handed to reading", of: app)
        // Verify the saved-text handoff without depending on installed speech
        // voices, producing audio or starting a model/permission workflow.
    }

    func testCleaningTypedTextKeepsOriginalWhenSavedAndReopened() {
        let app = launchIsolatedApp()
        let original = "Um, meet at 2pm, actually 3pm."
        let cleaned = "Meet at 3pm."
        app.buttons["tool.dictate"].tap()
        let draft = app.textViews["dictate.draft"]
        XCTAssertTrue(draft.waitForExistence(timeout: 5))
        reveal(draft, in: app)
        draft.tap(); draft.typeText(original)
        let done = app.buttons["Done"]
        if done.exists && done.isHittable { done.tap() }
        let cleanup = app.buttons["Clean up"]
        reveal(cleanup, in: app); cleanup.tap()
        XCTAssertEqual(draft.value as? String, cleaned)
        let save = app.buttons["dictate.save"]
        reveal(save, in: app); save.tap()
        app.navigationBars.buttons.firstMatch.tap()
        selectTab("Saved", in: app)
        let title = app.staticTexts[cleaned].firstMatch
        XCTAssertTrue(title.waitForExistence(timeout: 5)); title.tap()
        XCTAssertEqual(app.textViews["Saved text"].value as? String, cleaned)
        let originalDisclosure = app.buttons["Original"]
        reveal(originalDisclosure, in: app); originalDisclosure.tap()
        XCTAssertTrue(app.staticTexts[original].waitForExistence(timeout: 5))
    }

    func testIndependentWallpaperEntryCanCreateAndReopenAStarter() {
        let app = launchIsolatedApp()
        attachScreenshot("Tools home", of: app)
        XCTAssertTrue(app.buttons["tool.read"].exists)
        XCTAssertTrue(app.buttons["tool.markup"].exists)
        let wallpaper = app.buttons["tool.wallpaper"]
        reveal(wallpaper, in: app)
        wallpaper.tap()
        let choose = app.buttons["wallpaper.choose"]
        XCTAssertTrue(choose.waitForExistence(timeout: 5))
        reveal(choose, in: app)
        XCTAssertTrue(choose.isEnabled)
        // Use the bundled/generated starter to complete the job without Photos
        // permission or any personal images.
        let starter = app.buttons["Use Coast picture"]
        reveal(starter, in: app); starter.tap()
        XCTAssertTrue(app.navigationBars["Coast"].waitForExistence(timeout: 10))
        app.navigationBars.buttons.firstMatch.tap()
        selectTab("Saved", in: app)
        let saved = app.staticTexts["Coast"].firstMatch
        XCTAssertTrue(saved.waitForExistence(timeout: 5)); saved.tap()
        XCTAssertTrue(app.navigationBars["Coast"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["A calmer screen."].exists)
        attachScreenshot("Coast wallpaper editor", of: app)
        app.navigationBars.buttons.firstMatch.tap()
        selectTab("Tools", in: app)
        XCTAssertTrue(app.buttons["tool.dictate"].waitForExistence(timeout: 5))
    }

    func testFreshTestLaunchStartsWithEmptySavedCollection() {
        let app = launchIsolatedApp()
        selectTab("Saved", in: app)
        XCTAssertTrue(app.staticTexts["Your useful things, kept."].waitForExistence(timeout: 5))
        XCTAssertFalse(app.textViews["Saved text"].exists)
        selectTab("Tools", in: app)
        XCTAssertTrue(app.buttons["tool.dictate"].waitForExistence(timeout: 5))
    }

    func testMarkupNameKeepsKeyboardFocusAcrossCanvasUpdatesAndReopens() {
        let app = launchIsolatedApp()
        let wallpaper = app.buttons["tool.wallpaper"]
        reveal(wallpaper, in: app); wallpaper.tap()
        let starter = app.buttons["wallpaper.starter.coast"]
        reveal(starter, in: app); starter.tap()
        XCTAssertTrue(app.navigationBars["Coast"].waitForExistence(timeout: 10))
        app.buttons["Image actions"].tap()
        let reuse = app.buttons["Mark up"]
        XCTAssertTrue(reuse.waitForExistence(timeout: 5)); reuse.tap()
        XCTAssertTrue(app.buttons["Undo drawing"].waitForExistence(timeout: 5))
        let name = app.textFields["Name this image"]
        reveal(name, in: app)
        name.tap()
        // Separate events allow a SwiftUI/canvas update between characters.
        // The drawing canvas must not reclaim focus from the name field.
        name.typeText(" A")
        XCTAssertEqual(name.value as? String, "Coast A")
        name.typeText(" B")
        XCTAssertEqual(name.value as? String, "Coast A B")
        attachScreenshot("Markup name retains editing focus", of: app)
        app.navigationBars.buttons.firstMatch.tap()
        app.navigationBars.buttons.firstMatch.tap()
        selectTab("Saved", in: app)
        let renamed = app.staticTexts["Coast A B"].firstMatch
        XCTAssertTrue(renamed.waitForExistence(timeout: 5)); renamed.tap()
        let reopenedName = app.textFields["Name this image"]
        XCTAssertTrue(reopenedName.waitForExistence(timeout: 5))
        XCTAssertEqual(reopenedName.value as? String, "Coast A B")
    }
}
