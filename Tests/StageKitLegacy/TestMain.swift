import AppKit

@main
struct TestRunner {
    static func main() {
        let args = Array(CommandLine.arguments.dropFirst())
        guard args.isEmpty || args == ["--ci"] || args == ["--scenes-only"] else {
            print("Usage: StageMarkTests [--ci | --scenes-only]")
            exit(2)
        }
        let scenesOnly = args == ["--scenes-only"]
        let hostedCI = args == ["--ci"]
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.accessory)
        if !scenesOnly { NSApp.finishLaunching() }
        let suite = CoreTests()
        let integration = IntegrationTests()
        let scenes = SceneTests()
        let assets = SceneAssetTests()
        let demo = DemoModeTests()
        let viewportFit = ViewportFitTests()
        let logoImport = LogoImportTests()
        let workbench = WorkbenchModuleTests()
        var tests: [(String, () throws -> Void)] = [
            ("full-height frame persistence and edges", viewportFit.testFullHeightSurvivesSavingAndReachesBothEdges),
            ("maximum frame size across displays", viewportFit.testMaximumSizeFitsDisplayAndPreservesScreenShape),
            ("full-height export and live geometry", viewportFit.testExportAndLiveScreenUseFullHeightBorder),
            ("logo native WebP decoding and alpha", logoImport.testWebPAndTransparentPadding),
            ("logo image orientation and rejection", logoImport.testOrientationAndInvalidImages),
            ("logo paste image and file persistence", logoImport.testPasteImageAndFilePersistence),
            ("desktop verification waits for macOS and times out safely", scenes.testDesktopVerificationWaitsForMacOSAndStopsAtTimeout),
            ("scene search keeps customer selection consistent", scenes.testSceneSearchSelectsOnlyMatchingCustomers),
            ("desktop recovery across interrupted scene switch", scenes.testDesktopRecoverySurvivesInterruptedSwitch),
            ("scene persistence and bounds", scenes.testSceneRoundTripAndBounds),
            ("scene path and number validation", scenes.testUnsafeImagePathsAndNumbersRejected),
            ("scene corrupt and future archive safety", scenes.testCorruptAndFutureArchivesPreserved),
            ("scene duplicate ID validation", scenes.testDuplicateIDsRejected),
            ("phone geometry across display shapes", scenes.testPhoneStaysWithinWideAndTallDisplays),
            ("scene rendering and durable image import", scenes.testRenderAndImportedImageSurviveSourceRemoval),
            ("legacy scene decoding and logo validation", assets.testLegacyScenesAndLogoValidation),
            ("starter selection preserves saved customers", assets.testStartersNeverOverwriteSavedCustomers),
            ("logo import replacement and missing-file recovery", assets.testLogoImportReplacementAndRecovery),
            ("logo pixels and starter compositions", assets.testLogoPixelsCornersAndSceneCompositions),
            ("viewport geometry and saved device profiles", demo.testViewportGeometryAndProfiles),
            ("independent Space recovery and manual changes", demo.testIndependentSpaceRecoveryAndManualChanges),
            ("capture source identity and stale frames", demo.testCaptureSourceIdentityAndStaleFrames),
            ("presentation controls intentional reveal and retention", demo.testPresentationControlsRevealAndRetention),
            ("hand transparency persistence and no stretching", demo.testHandTransparencyPersistenceAndNoStretch),
            ("saved logo adoption reuse and removal", demo.testLogoLibraryMigrationReuseAndRemoval),
            ("library customization and corrupt file safety", demo.testLibraryCustomizationAndCorruptFileSafety),
            ("unified migration preserves malformed originals and preview edits", workbench.testMigrationCopiesPreviewOnceAndPreservesMalformedFiles),
            ("unified migration rejects symlinks and retries", workbench.testMigrationRejectsSymlinksAndRetriesCleanly),
            ("line hit testing", suite.testLineHitTestingUsesSegmentsNotBoundingBox),
            ("rectangle edge hit testing", suite.testRectangleOnlyErasesAtBorder),
            ("ellipse edge hit testing", suite.testEllipseOnlyErasesAtBorder),
            ("arrowhead hit testing", suite.testArrowHeadIsErasable),
            ("degenerate stroke", suite.testDegenerateStrokeDoesNotDivideByZero),
            ("constrained shapes", suite.testShiftConstrainedShapesAcrossQuadrants),
            ("undo redo divergent edit", suite.testUndoRedoAndDivergentEdit),
            ("eraser transaction", suite.testEraserDragIsOneUndoableAction),
            ("no-op eraser", suite.testNoOpEraserPreservesUndoHistory),
            ("undo clear", suite.testClearIsUndoableAndEmptyClearDoesNotAddHistory),
            ("bounded history", suite.testHistoryIsBounded),
            ("fade lifecycle", suite.testFadeTimingAndExpiredInkCannotResurrect),
            ("countdown pause resume sleep", suite.testCountdownPauseResumeAndSleep),
            ("countdown formatting", suite.testCountdownRoundingAndHours),
            ("board persistence", suite.testBoardPersistenceRoundTripAndSeparateDisplays),
            ("corrupt board safety", suite.testCorruptBoardFailsWithoutOverwriting),
            ("missing and future board versions", suite.testMissingBoardStartsEmptyAndUnknownVersionFails),
            ("shortcut uniqueness", suite.testDefaultShortcutsAreUniqueAndComplete),
            ("settings persistence and bounds", suite.testPreferencesPersistAndClamp),
            ("settings recovery", suite.testCorruptPreferencesArePreservedForRecovery),
            ("actual rendering for every tool", suite.testAllToolsRenderToRealPixels),
            ("native mouse handlers and text commit", integration.testActualMouseHandlersAndTextCommit),
            ("first stroke after activation", integration.testFirstStrokeAfterActivationReachesInactiveCanvas),
            ("native drawing lifecycle and board isolation", integration.testDrawingLifecycleAndBoardIsolation),
            ("global shortcut registration and release", integration.testShortcutRegistrationAndRelease)
        ]
        if scenesOnly {
            tests = Array(tests.prefix { $0.0 != "line hit testing" })
        } else if hostedCI {
            print("SKIP live menu-bar popover regression in --ci mode; run scripts/test.zsh on an interactive Mac for full coverage")
        } else {
            tests.append(("menu bar and non-destructive quick adjustments", integration.testMenuBarAccessAndQuickAdjustmentsPreserveBoard))
        }
        if !scenesOnly { tests.append(("embedded navigation and recording suspension", workbench.testEmbeddedCallbacksAndSuspendedShortcutSettings)) }
        for (name, test) in tests {
            let before = assertionFailures
            do { try test() } catch { assertionFailures += 1; print("FAIL \(name): \(error)") }
            if assertionFailures == before { print("PASS \(name)") }
        }
        print("\(tests.count) tests · \(assertionCount) assertions · \(assertionFailures) failures")
        exit(assertionFailures == 0 ? 0 : 1)
    }
}
