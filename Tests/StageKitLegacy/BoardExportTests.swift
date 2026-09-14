import AppKit

final class BoardExportTests {
    func testBoardPixelsOrientationTextAndRetinaScale() throws {
        let red = InkColor(NSColor(srgbRed: 1, green: 0, blue: 0, alpha: 1))
        let line = Annotation(tool: .line, color: red, width: 6,
            points: [InkPoint(CGPoint(x: 10, y: 12)), InkPoint(CGPoint(x: 55, y: 12))])
        let marker = Annotation(tool: .highlighter, color: red, width: 10,
            points: [InkPoint(CGPoint(x: 10, y: 40)), InkPoint(CGPoint(x: 55, y: 40))])
        let text = Annotation(tool: .text, color: .black, width: 1,
            points: [InkPoint(CGPoint(x: 65, y: 10))], text: "Top", fontSize: 14)
        let export = BoardImageExport(style: .white, size: CGSize(width: 120, height: 90),
                                      annotations: [line, marker, text], scale: 2)
        let bitmap = NSBitmapImageRep(data: try export.png())!
        XCTAssertEqual(bitmap.pixelsWide, 240); XCTAssertEqual(bitmap.pixelsHigh, 180)
        let top = bitmap.colorAt(x: 50, y: 24)!.usingColorSpace(.deviceRGB)!
        let bottom = bitmap.colorAt(x: 50, y: 156)!.usingColorSpace(.deviceRGB)!
        XCTAssertGreaterThan(top.redComponent, 0.9)
        XCTAssertTrue(top.greenComponent < bottom.greenComponent - 0.5,
                      "Ink at the top of the canvas must stay at the top of the PNG, across display colour profiles")
        XCTAssertGreaterThan(bottom.greenComponent, 0.9)
        let highlighted = bitmap.colorAt(x: 50, y: 80)!.usingColorSpace(.deviceRGB)!
        XCTAssertTrue(highlighted.greenComponent > 0.55 && highlighted.greenComponent < 0.85,
                      "Highlighter transparency must blend with the opaque board background")
        var textPixels = 0
        for y in 20..<60 { for x in 130..<230 {
            if bitmap.colorAt(x: x, y: y)!.usingColorSpace(.deviceRGB)!.redComponent < 0.3 { textPixels += 1 }
        } }
        XCTAssertGreaterThan(textPixels, 30, "Committed text must render in its top-left canvas location")
        let black = BoardImageExport(style: .black, size: CGSize(width: 60, height: 40), annotations: [])
        let dark = NSBitmapImageRep(data: try black.png())!
        for point in [(0, 0), (30, 20), (59, 39)] {
            let pixel = dark.colorAt(x: point.0, y: point.1)!.usingColorSpace(.deviceRGB)!
            XCTAssertEqual(Double(pixel.alphaComponent), 1, accuracy: 0.001)
            XCTAssertTrue(pixel.redComponent < 0.1 && pixel.blueComponent < 0.15)
        }
    }

    func testSnapshotPersistenceBoundsAndInvalidInput() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("BoardExportTests-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let ink = Annotation(tool: .rectangle, color: .coral, width: 4,
            points: [InkPoint(CGPoint(x: 8, y: 8)), InkPoint(CGPoint(x: 55, y: 35))])
        let history = CanvasHistory([ink])
        let snapshot = BoardImageExport(style: .white, size: CGSize(width: 64, height: 48), annotations: history.annotations)
        history.clear()
        XCTAssertEqual(snapshot.annotations, [ink], "The save panel must use its original immutable snapshot")
        let output = root.appendingPathComponent("Board.png")
        let data = try snapshot.png(); try data.write(to: output, options: .atomic)
        XCTAssertEqual(try Data(contentsOf: output), data)
        XCTAssertNotNil(NSImage(contentsOf: output))
        var oversized = snapshot
        oversized = BoardImageExport(style: .white, size: CGSize(width: 9000, height: 20), annotations: [], scale: 2)
        let bounded = NSBitmapImageRep(data: try oversized.png())!
        XCTAssertEqual(bounded.pixelsWide, 8192)
        XCTAssertTrue(bounded.pixelsHigh > 0 && bounded.pixelsWide * bounded.pixelsHigh <= 32_000_000)
        for bad in [CGSize.zero, CGSize(width: CGFloat.nan, height: 10), CGSize(width: 10, height: CGFloat.infinity)] {
            XCTAssertThrowsError(try BoardImageExport(style: .white, size: bad, annotations: []).png())
        }
        var invalid = ink; invalid.points[0].x = .nan
        XCTAssertThrowsError(try BoardImageExport(style: .white, size: snapshot.size, annotations: [invalid]).png())
        invalid = ink; invalid.color.g = .infinity
        XCTAssertThrowsError(try BoardImageExport(style: .white, size: snapshot.size, annotations: [invalid]).png())
    }

    func testPrivateClipboardPNGAndFailurePreservation() throws {
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        pasteboard.setString("Existing clipboard fixture", forType: .string)
        let invalid = BoardImageExport(style: .white, size: .zero, annotations: [])
        XCTAssertThrowsError(try invalid.copy(to: pasteboard))
        XCTAssertEqual(pasteboard.string(forType: .string), "Existing clipboard fixture")
        let valid = BoardImageExport(style: .white, size: CGSize(width: 80, height: 60), annotations: [])
        try valid.copy(to: pasteboard)
        let copied = pasteboard.data(forType: .png)
        XCTAssertNotNil(copied)
        XCTAssertEqual(NSBitmapImageRep(data: copied!)?.pixelsWide, 80)
        XCTAssertTrue(pasteboard.string(forType: .string) == nil, "Copy board writes image data, not a file path")
    }
}
