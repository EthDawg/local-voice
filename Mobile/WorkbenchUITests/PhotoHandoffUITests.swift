import XCTest

@MainActor
final class PhotoHandoffUITests: XCTestCase {
    private func launchLocalOnly() -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        // Both the library and handoff directory are disposable. The handoff
        // model receives allowsCloudAccess: false even in a provisioned build.
        app.launchArguments = ["--ui-testing", "--ui-testing-handoff"]
        app.launch()
        let entry = app.buttons["tool.photoHandoff"]
        XCTAssertTrue(entry.waitForExistence(timeout: 10))
        reveal(entry, in: app); entry.tap()
        XCTAssertTrue(app.navigationBars["Photo for Mac"].waitForExistence(timeout: 5))
        return app
    }

    private func reveal(_ element: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<8 {
            if element.exists && element.isHittable { return }
            let scroll = app.scrollViews.firstMatch
            let start = scroll.coordinate(withNormalizedOffset: CGVector(dx: 0.98, dy: 0.8))
            let end = scroll.coordinate(withNormalizedOffset: CGVector(dx: 0.98, dy: 0.2))
            start.press(forDuration: 0.01, thenDragTo: end)
        }
        XCTAssertTrue(element.isHittable)
    }

    private func screenshot(_ title: String, app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = title; attachment.lifetime = .keepAlways; add(attachment)
    }

    func testChosenSampleStaysLocalAndReopensFromSaved() {
        let app = launchLocalOnly()
        let sample = app.buttons["handoff.sample"]
        reveal(sample, in: app); sample.tap()
        let name = app.textFields["handoff.name"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        reveal(name, in: app); name.tap(); name.typeText("Fixture whiteboard")
        let done = app.buttons["Done"]
        if done.exists && done.isHittable { done.tap() }
        XCTAssertFalse(app.buttons["handoff.send"].isEnabled)
        screenshot("Synthetic photo preview - cloud disabled", app: app)
        let keep = app.buttons["handoff.keep"]
        reveal(keep, in: app); keep.tap()
        let notice = app.staticTexts["handoff.notice"]
        XCTAssertTrue(notice.waitForExistence(timeout: 10))
        XCTAssertEqual(notice.label, "Original kept on this device.")
        app.navigationBars.buttons.firstMatch.tap()

        let label = NSPredicate(format: "label == %@", "Saved")
        let queries = [app.buttons.matching(label), app.cells.matching(label), app.otherElements.matching(label)]
        let savedTab = queries.flatMap { $0.allElementsBoundByIndex }.first { $0.isHittable }
        XCTAssertNotNil(savedTab); savedTab?.tap()
        XCTAssertTrue(app.navigationBars["Saved"].waitForExistence(timeout: 5))
        let row = app.descendants(matching: .any).matching(identifier: "handoff.photoRow").firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5)); row.tap()
        XCTAssertTrue(app.navigationBars["Fixture whiteboard"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Share a copy"].exists)
        XCTAssertFalse(app.buttons["handoff.enable"].isEnabled)
        XCTAssertFalse(app.staticTexts["In iCloud"].exists)
        screenshot("Saved local photo - synthetic handoff fixture", app: app)
    }

    func testLeavingAnUnkeptPhotoRequiresAChoiceAndDiscardDoesNotSend() {
        let app = launchLocalOnly()
        let sample = app.buttons["handoff.sample"]
        reveal(sample, in: app); sample.tap()
        XCTAssertTrue(app.textFields["handoff.name"].waitForExistence(timeout: 5))
        app.navigationBars.buttons["Back"].tap()
        XCTAssertTrue(app.buttons["Discard preview"].waitForExistence(timeout: 5))
        // A stable action identifier also works in the iPad confirmation popover.
        let discard = app.buttons.matching(identifier: "handoff.discardAndLeave").firstMatch
        XCTAssertTrue(discard.waitForExistence(timeout: 5)); discard.tap()
        XCTAssertTrue(app.navigationBars["Workbench"].waitForExistence(timeout: 5))
        let entry = app.buttons["tool.photoHandoff"]
        reveal(entry, in: app); entry.tap()
        XCTAssertFalse(app.textFields["handoff.name"].exists)
        XCTAssertFalse(app.descendants(matching: .any).matching(identifier: "handoff.photoRow").firstMatch.exists)
    }
}
