import AppKit

final class FloatingControlGeometryTests {
    func testAllTargetsAreDistinctFiniteAndBounded() throws {
        let size = NSSize(width: 76, height: 40)
        let displays = [NSRect(x: 0, y: 48, width: 1440, height: 850),
                        NSRect(x: -1920, y: -900, width: 1920, height: 1080)]
        for display in displays {
            let targets = FloatingControlGeometry.targets(size: size, visibleFrame: display)
            XCTAssertEqual(targets.map(\.anchor), FloatingControlAnchor.allCases)
            for target in targets {
                XCTAssertTrue(display.insetBy(dx: 16, dy: 16).contains(target.frame))
                XCTAssertEqual(targets.filter { $0.frame == target.frame }.count, 1)
                XCTAssertEqual(FloatingControlGeometry.nearestAnchor(to: target.frame, in: display), target.anchor)
            }
        }
        let tiny = NSRect(x: -20, y: -50, width: 30, height: 20)
        let targets = FloatingControlGeometry.targets(size: NSSize(width: 304, height: 192), visibleFrame: tiny)
        XCTAssertEqual(targets.count, 1)
        XCTAssertEqual(targets.first?.anchor, .topLeft)
        XCTAssertEqual(targets.first?.frame, tiny)
        let narrow = NSRect(x: -500, y: 50, width: 100, height: 400)
        let narrowTargets = FloatingControlGeometry.targets(size: NSSize(width: 304, height: 192), visibleFrame: narrow)
        XCTAssertEqual(narrowTargets.count, 3)
        XCTAssertEqual(narrowTargets.map(\.anchor), [.topLeft, .left, .bottomLeft])
        for target in narrowTargets {
            XCTAssertTrue(narrow.contains(target.frame))
            XCTAssertTrue([target.frame.minX, target.frame.minY, target.frame.width, target.frame.height].allSatisfy(\.isFinite))
        }
        for invalid in [NSSize.zero, NSSize(width: CGFloat.nan, height: 40), NSSize(width: 76, height: CGFloat.infinity)] {
            XCTAssertTrue(FloatingControlGeometry.targets(size: invalid, visibleFrame: displays[0]).isEmpty)
        }
        XCTAssertTrue(FloatingControlGeometry.targets(size: size, visibleFrame: .zero).isEmpty)
        XCTAssertTrue(FloatingControlGeometry.targets(size: size, visibleFrame: NSRect(x: CGFloat.nan, y: 0, width: 100, height: 100)).isEmpty)
    }

    func testGuideLayoutPreservesTargetsAndFlipsDisplayCoordinates() throws {
        let display = NSRect(x: -1600, y: -180, width: 1600, height: 1000)
        let drag = NSRect(x: -900, y: 300, width: 76, height: 40)
        guard let layout = FloatingControlGuideLayout(controlFrame: drag, visibleFrame: display, activeAnchor: .bottomRight) else {
            XCTAssertTrue(false, "A valid drag must expose all destinations"); return
        }
        XCTAssertEqual(layout.targets.count, 8)
        XCTAssertEqual(layout.activeID, .bottomRight)
        XCTAssertFalse(layout.usesCompactMarks)
        for target in layout.targets {
            let local = layout.localFrame(target.frame)
            XCTAssertEqual(local.minX, target.frame.minX - display.minX)
            XCTAssertEqual(local.maxY, display.maxY - target.frame.minY)
            XCTAssertTrue(NSRect(origin: .zero, size: display.size).contains(local))
            if target.anchor == .topLeft { XCTAssertEqual(local.origin, NSPoint(x: 16, y: 16)) }
            if target.anchor == .bottomRight { XCTAssertEqual(local.origin, NSPoint(x: 1508, y: 944)) }
        }
        let narrow = NSRect(x: -500, y: 50, width: 100, height: 400)
        let large = NSRect(x: -500, y: 50, width: 304, height: 192)
        guard let compact = FloatingControlGuideLayout(controlFrame: large, visibleFrame: narrow, activeAnchor: .topRight) else {
            XCTAssertTrue(false); return
        }
        XCTAssertTrue(compact.usesCompactMarks)
        XCTAssertEqual(compact.activeID, .topLeft, "Coincident named positions highlight the same deduplicated target")
        for target in compact.targets {
            XCTAssertTrue(narrow.contains(compact.markFrame(for: target)))
            XCTAssertEqual(compact.markFrame(for: target).midX, target.frame.midX)
            XCTAssertEqual(compact.markFrame(for: target).midY, target.frame.midY)
            XCTAssertTrue(narrow.contains(compact.activeOutline(for: target)))
        }
    }

    func testGuideStateClearsWhenDragOrDisplayEnds() throws {
        let screen = NSRect(x: -1600, y: -180, width: 1600, height: 1000)
        let frame = NSRect(x: -900, y: 300, width: 76, height: 40)
        let freeDrag = FloatingControlGuideLayout(controlFrame: frame, visibleFrame: screen, activeAnchor: nil)
        XCTAssertEqual(freeDrag?.targets.count, 8, "All destinations stay discoverable away from snapping distance")
        XCTAssertTrue(freeDrag?.activeID == nil)
        XCTAssertTrue(FloatingControlGuideLayout(controlFrame: nil, visibleFrame: screen, activeAnchor: .right) == nil,
                      "No drag means no guides, including when a previous anchor remains selected")
        XCTAssertTrue(FloatingControlGuideLayout(controlFrame: frame, visibleFrame: .zero, activeAnchor: .right) == nil)
        XCTAssertTrue(FloatingControlGuideLayout(controlFrame: .zero, visibleFrame: screen, activeAnchor: .right) == nil)
        XCTAssertTrue(FloatingControlGuideLayout(controlFrame: NSRect(x: CGFloat.nan, y: 0, width: 76, height: 40),
                                                visibleFrame: screen, activeAnchor: .right) == nil)
        let replacementScreen = NSRect(x: 0, y: 48, width: 1024, height: 720)
        let recovered = FloatingControlGeometry.clamp(frame, to: replacementScreen)
        let nextDrag = FloatingControlGuideLayout(controlFrame: recovered, visibleFrame: replacementScreen, activeAnchor: nil)
        XCTAssertEqual(nextDrag?.targets.count, 8)
        XCTAssertTrue(nextDrag?.targets.allSatisfy { replacementScreen.contains($0.frame) } == true)
    }

    func testAnchorsBoundsAndResize() throws {
        let tile = NSSize(width: 76, height: 40), expanded = NSSize(width: 304, height: 192)
        let displays = [NSRect(x: 0, y: 48, width: 1440, height: 850),
                        NSRect(x: -1920, y: -900, width: 1920, height: 1080),
                        NSRect(x: 1440, y: 300, width: 1024, height: 768)]
        XCTAssertEqual(Set(FloatingControlAnchor.allCases.map(\.id)).count, 8)
        XCTAssertTrue(FloatingControlAnchor.allCases.allSatisfy { !$0.title.isEmpty })
        for display in displays {
            for anchor in FloatingControlAnchor.allCases {
                let small = FloatingControlGeometry.frame(anchor: anchor, size: tile, visibleFrame: display)
                let large = FloatingControlGeometry.frame(anchor: anchor, size: expanded, visibleFrame: display)
                XCTAssertTrue(display.insetBy(dx: 16, dy: 16).contains(small))
                XCTAssertTrue(display.insetBy(dx: 16, dy: 16).contains(large))
                XCTAssertEqual(small.size, tile); XCTAssertEqual(large.size, expanded)
                switch anchor {
                case .topLeft: XCTAssertEqual(small.minX, large.minX); XCTAssertEqual(small.maxY, large.maxY)
                case .top: XCTAssertEqual(small.midX, large.midX); XCTAssertEqual(small.maxY, large.maxY)
                case .topRight: XCTAssertEqual(small.maxX, large.maxX); XCTAssertEqual(small.maxY, large.maxY)
                case .left: XCTAssertEqual(small.minX, large.minX); XCTAssertEqual(small.midY, large.midY)
                case .right: XCTAssertEqual(small.maxX, large.maxX); XCTAssertEqual(small.midY, large.midY)
                case .bottomLeft: XCTAssertEqual(small.minX, large.minX); XCTAssertEqual(small.minY, large.minY)
                case .bottom: XCTAssertEqual(small.midX, large.midX); XCTAssertEqual(small.minY, large.minY)
                case .bottomRight: XCTAssertEqual(small.maxX, large.maxX); XCTAssertEqual(small.minY, large.minY)
                }
                var placement = PresentationControlPlacement(anchor: anchor)
                XCTAssertEqual(placement.frame(size: expanded, in: display), large)
                placement.move(to: large, in: display, anchor: anchor)
                XCTAssertEqual(placement.frame(size: tile, in: display), small)
            }
        }
        let right = PresentationControlPlacement().frame(size: tile, in: displays[0])
        XCTAssertEqual(right.maxX, displays[0].maxX - 16)
        XCTAssertEqual(right.midY, displays[0].midY)
        let tiny = NSRect(x: -20, y: 100, width: 30, height: 20)
        let fitting = FloatingControlGeometry.frame(anchor: .topRight, size: expanded, visibleFrame: tiny)
        XCTAssertEqual(fitting, tiny, "A tiny visible frame must reduce margin before shrinking controls")
        XCTAssertEqual(FloatingControlGeometry.clamp(NSRect(x: CGFloat.nan, y: CGFloat.infinity, width: CGFloat.nan, height: 20), to: displays[0]).width, 0)
        XCTAssertEqual(FloatingControlGeometry.frame(anchor: .right, size: tile, visibleFrame: .zero), .zero)
    }

    func testSnapThresholdsAndDisplayRecovery() throws {
        let display = NSRect(x: -1600, y: -180, width: 1600, height: 1000)
        let size = NSSize(width: 76, height: 40)
        for anchor in FloatingControlAnchor.allCases {
            let target = FloatingControlGeometry.frame(anchor: anchor, size: size, visibleFrame: display)
            XCTAssertEqual(FloatingControlGeometry.nearestAnchor(to: target, in: display), anchor)
            XCTAssertEqual(FloatingControlGeometry.nearestAnchor(to: target.offsetBy(dx: 28, dy: 0), in: display), anchor)
            XCTAssertTrue(FloatingControlGeometry.nearestAnchor(to: target.offsetBy(dx: 28.1, dy: 0), in: display) == nil)
            XCTAssertTrue(FloatingControlGeometry.nearestAnchor(to: target.offsetBy(dx: 22, dy: 22), in: display) == nil,
                          "Snap threshold is radial, not an unbounded edge strip")
        }
        let right = FloatingControlGeometry.frame(anchor: .right, size: size, visibleFrame: display)
        XCTAssertTrue(FloatingControlGeometry.nearestAnchor(to: right.offsetBy(dx: 0, dy: 150), in: display) == nil,
                      "Ordinary positions along an edge must not snap unexpectedly to its centre")
        XCTAssertTrue(FloatingControlGeometry.nearestAnchor(to: right, in: display, threshold: -.infinity) == nil)
        let removedScreenFrame = NSRect(x: 3200, y: 2000, width: 304, height: 192)
        let recovered = FloatingControlGeometry.clamp(removedScreenFrame, to: display)
        XCTAssertTrue(display.insetBy(dx: 16, dy: 16).contains(recovered))
        XCTAssertEqual(recovered.maxX, display.maxX - 16); XCTAssertEqual(recovered.maxY, display.maxY - 16)
        var placement = PresentationControlPlacement()
        let free = NSRect(x: -1000, y: 130, width: 76, height: 40)
        placement.move(to: free, in: display, anchor: nil)
        XCTAssertEqual(placement.frame(size: size, in: display).minX, free.minX, accuracy: 0.001)
        XCTAssertEqual(placement.frame(size: size, in: display).minY, free.minY, accuracy: 0.001)
        let other = NSRect(x: 0, y: 0, width: 800, height: 600)
        XCTAssertTrue(other.contains(placement.frame(size: NSSize(width: 304, height: 192), in: other)))
        let data = try JSONEncoder().encode(placement)
        XCTAssertEqual(try JSONDecoder().decode(PresentationControlPlacement.self, from: data).validated(), placement)
        XCTAssertThrowsError(try PresentationControlPlacement(version: 2).validated())
        XCTAssertThrowsError(try PresentationControlPlacement(x: .nan).validated())
        XCTAssertFalse(PresentationControlsPolicy().isExpanded, "Restored placement never restores expansion")
    }
}
