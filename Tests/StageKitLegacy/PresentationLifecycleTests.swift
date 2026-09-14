import AppKit

final class PresentationLifecycleTests {
    func testModeChangesKeepPresentationAndEndClosesOnce() {
        func fullScreenCommand(_ text: String?, _ flags: NSEvent.ModifierFlags) -> Bool {
            PresentationControlsPolicy.isFullScreenCommand(characters: text, modifiers: flags)
        }
        XCTAssertTrue(fullScreenCommand("f", [.control, .command]))
        XCTAssertTrue(fullScreenCommand("F", [.control, .command, .capsLock]), "Caps Lock must not disable the standard fullscreen command")
        XCTAssertFalse(fullScreenCommand("f", [.command]), "Command-F remains available for Find")
        XCTAssertFalse(fullScreenCommand("f", [.control]))
        XCTAssertFalse(fullScreenCommand("f", [.control, .command, .option]))
        XCTAssertFalse(fullScreenCommand("f", [.control, .command, .shift]))
        XCTAssertFalse(fullScreenCommand("r", [.control, .command]), "Reconnect is a separate command")
        XCTAssertFalse(fullScreenCommand(nil, [.control, .command]))
        var state = PresentationLifecycle()
        state.willEnter()
        XCTAssertEqual(state.didEnter(), .none)
        XCTAssertTrue(state.isFullScreen)
        state.willExit()
        XCTAssertEqual(state.didExit(), .none, "Leaving fullscreen returns to the window without ending capture")
        XCTAssertFalse(state.ending); XCTAssertFalse(state.finished); XCTAssertFalse(state.isFullScreen)
        state.willEnter(); XCTAssertEqual(state.didEnter(), .none)
        XCTAssertEqual(state.requestEnd(), .exitFullScreen)
        XCTAssertEqual(state.requestEnd(), .none, "Repeated Escape/close cannot start another transition")
        state.willExit(); XCTAssertEqual(state.didExit(), .finish)
        state.complete()
        XCTAssertEqual(state.didExit(), .none); XCTAssertEqual(state.requestEnd(), .none)
        var windowed = PresentationLifecycle()
        XCTAssertEqual(windowed.requestEnd(), .finish, "A windowed demo ends without a fullscreen transition")
    }

    func testEndDuringNativeTransitionsAndFailureRecovery() {
        var entering = PresentationLifecycle()
        entering.willEnter()
        XCTAssertEqual(entering.requestEnd(), .none, "End waits for the native entry transition")
        XCTAssertEqual(entering.didEnter(), .exitFullScreen)
        entering.willExit(); XCTAssertEqual(entering.didExit(), .finish)
        var exiting = PresentationLifecycle()
        exiting.willEnter(); _ = exiting.didEnter(); exiting.willExit()
        XCTAssertEqual(exiting.requestEnd(), .none, "End must not toggle back into fullscreen during exit")
        XCTAssertEqual(exiting.didExit(), .finish)
        var failure = PresentationLifecycle()
        failure.willEnter(); XCTAssertEqual(failure.failedToEnter(), .none)
        XCTAssertFalse(failure.ending, "A failed fullscreen entry leaves a usable presentation window")
        failure.willEnter(); _ = failure.requestEnd(); XCTAssertEqual(failure.failedToEnter(), .finish)
        var exitFailure = PresentationLifecycle()
        exitFailure.willEnter(); _ = exitFailure.didEnter(); exitFailure.willExit()
        XCTAssertEqual(exitFailure.failedToExit(), .none, "A failed mode change must not stop capture")
        XCTAssertTrue(exitFailure.isFullScreen)
        _ = exitFailure.requestEnd(); exitFailure.willExit()
        XCTAssertEqual(exitFailure.failedToExit(), .finish, "An explicit end still cleans up if native exit fails")
    }
}
