import XCTest
import UIKit
@testable import WorkbenchMobile

@MainActor final class MobilePersonaCardTests: XCTestCase {
    private func library() throws -> SceneLibraryModel {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("MobilePersonaCardTests-" + UUID().uuidString)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }; return SceneLibraryModel(directory: url)
    }
    private func solidPortrait() throws -> Data {
        let format = UIGraphicsImageRendererFormat(); format.scale = 1; format.opaque = false
        return try XCTUnwrap(UIGraphicsImageRenderer(size: CGSize(width: 100, height: 200), format: format).image { context in
            UIColor.red.setFill(); context.fill(CGRect(x: 0, y: 0, width: 100, height: 200))
        }.pngData())
    }
    private func pixels(_ image: UIImage) throws -> [UInt8] {
        let cg = try XCTUnwrap(image.cgImage); var bytes = [UInt8](repeating: 0, count: cg.width * cg.height * 4)
        try bytes.withUnsafeMutableBytes { storage in
            let context = try XCTUnwrap(CGContext(data: storage.baseAddress, width: cg.width, height: cg.height,
                bitsPerComponent: 8, bytesPerRow: cg.width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue))
            context.draw(cg, in: CGRect(x: 0, y: 0, width: cg.width, height: cg.height))
        }; return bytes
    }
    private func pixel(_ bytes: [UInt8], x: Int, y: Int) -> ArraySlice<UInt8> { bytes[(y * 480 + x) * 4..<(y * 480 + x) * 4 + 4] }
    private func count(_ bytes: [UInt8], matching: (UInt8, UInt8, UInt8, UInt8) -> Bool) -> Int {
        stride(from: 0, to: bytes.count, by: 4).filter { matching(bytes[$0], bytes[$0 + 1], bytes[$0 + 2], bytes[$0 + 3]) }.count
    }
    func testAllEightRealBundledPortraitsAreReadableAndRenderAtPortableSize() throws {
        let library = MobilePersonaPortraits()
        XCTAssertEqual(MobilePersonaPortraits.all.map(\.id), ["care-lead", "field-lead", "front-desk", "operations-lead", "logistics-lead", "care-coordinator", "hospitality-lead", "field-technician"])
        for starter in MobilePersonaPortraits.all {
            let data = try library.data(for: starter)
            XCTAssertNotNil(try MobilePersonaPortraits.thumbnail(data).cgImage)
            let card = try MobilePersonaCardSnapshot(portrait: data, label: starter.label, red: 0.08, green: 0.38, blue: 0.31)
            let image = try XCTUnwrap(UIImage(data: card.rendered)?.cgImage)
            XCTAssertEqual(image.width, 480); XCTAssertEqual(image.height, 600)
            XCTAssertEqual(card.style.portrait, SceneAsset.name(for: data))
        }
    }
    func testGeometryKeepsPortraitAspectAndTransparentRoundedCorners() throws {
        let data = try solidPortrait()
        let withLabel = try MobilePersonaCardSnapshot(portrait: data, label: "Field lead", red: 0.08, green: 0.38, blue: 0.31)
        let withoutLabel = try MobilePersonaCardSnapshot(portrait: data, label: "", red: 0.08, green: 0.38, blue: 0.31)
        let labeled = try pixels(XCTUnwrap(UIImage(data: withLabel.rendered)))
        let plain = try pixels(XCTUnwrap(UIImage(data: withoutLabel.rendered)))
        XCTAssertEqual(Array(pixel(labeled, x: 0, y: 0)), [0, 0, 0, 0])
        XCTAssertEqual(Array(pixel(labeled, x: 479, y: 599)), [0, 0, 0, 0])
        XCTAssertEqual(Array(pixel(labeled, x: 240, y: 300)), [255, 0, 0, 255])
        let edge = Array(pixel(labeled, x: 5, y: 300))
        XCTAssertEqual(edge[0], 20, accuracy: 2); XCTAssertEqual(edge[1], 97, accuracy: 2); XCTAssertEqual(edge[2], 79, accuracy: 2)
        let redLabeled = count(labeled) { $0 > 250 && $1 < 5 && $2 < 5 && $3 > 250 }
        let redPlain = count(plain) { $0 > 250 && $1 < 5 && $2 < 5 && $3 > 250 }
        // A 1:2 portrait fits 241×482 with a label, 291×582 without one.
        XCTAssertEqual(redLabeled, 241 * 482, accuracy: 1_500)
        XCTAssertEqual(redPlain, 291 * 582, accuracy: 2_000)
    }
    func testLabelContrastMatchesMacAndChangesActualRenderedPixels() throws {
        XCTAssertFalse(MobilePersonaCardRenderer.labelUsesBlack(red: 0, green: 0, blue: 0))
        XCTAssertTrue(MobilePersonaCardRenderer.labelUsesBlack(red: 1, green: 1, blue: 1))
        XCTAssertTrue(MobilePersonaCardRenderer.labelUsesBlack(red: 0.5, green: 0.5, blue: 0.5))
        let portrait = try solidPortrait()
        let dark = try MobilePersonaCardSnapshot(portrait: portrait, label: "Field lead", red: 0, green: 0, blue: 0)
        let light = try MobilePersonaCardSnapshot(portrait: portrait, label: "Field lead", red: 1, green: 1, blue: 1)
        let darkPixels = try pixels(XCTUnwrap(UIImage(data: dark.rendered))), lightPixels = try pixels(XCTUnwrap(UIImage(data: light.rendered)))
        XCTAssertGreaterThan(count(darkPixels) { $0 > 245 && $1 > 245 && $2 > 245 && $3 > 250 }, 100)
        XCTAssertGreaterThan(count(lightPixels) { $0 < 10 && $1 < 10 && $2 < 10 && $3 > 250 }, 100)
    }
    func testIndependentSceneSnapshotKeepsOriginalPortraitAndPlacement() throws {
        let library = try library()
        let portrait = try MobilePersonaPortraits().data(for: MobilePersonaPortraits.all[0])
        let first = try MobilePersonaCardSnapshot(portrait: portrait, label: "Care lead", red: 0.08, green: 0.38, blue: 0.31)
        let background = try library.importAsset(solidPortrait())
        let placement = ScenePersonaLayer(image: background, x: 0.17, y: 0.83, width: 0.24)
        let firstLayer = try first.install(in: library, preserving: placement)
        var scene = PortableScene(name: "First scene", background: background); scene.persona = firstLayer
        let record = try library.create(scene), copy = try library.duplicate(id: record.id)
        let updated = try MobilePersonaCardSnapshot(portrait: portrait, label: "Coordinator", red: 0.2, green: 0.25, blue: 0.8)
        let newLayer = try updated.install(in: library, preserving: firstLayer)
        scene.persona = newLayer; _ = try library.save(scene, expectedRevision: record.revision)
        XCTAssertEqual(newLayer.x, 0.17); XCTAssertEqual(newLayer.y, 0.83); XCTAssertEqual(newLayer.width, 0.24)
        XCTAssertNotEqual(newLayer.image, firstLayer.image)
        XCTAssertEqual(library.records.first(where: { $0.id == copy.id })?.scene.persona, firstLayer)
        let originalPackage = try library.package(for: copy.scene)
        XCTAssertEqual(originalPackage.assets[first.style.portrait], portrait)
        XCTAssertEqual(originalPackage.assets[firstLayer.image], first.rendered)
        let changedPackage = try library.package(for: scene)
        XCTAssertEqual(changedPackage.assets[newLayer.card!.portrait], portrait)
        XCTAssertEqual(changedPackage.assets[newLayer.image], updated.rendered)
    }
    func testMissingAndUnregisteredPortraitsFailWithoutCreatingPlaceholder() throws {
        let missing = MobilePersonaPortraits(directory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        XCTAssertThrowsError(try missing.data(for: MobilePersonaPortraits.all[0]))
        XCTAssertThrowsError(try MobilePersonaPortraits().data(for: MobilePersonaStarter(id: "../care-lead", label: "Care lead")))
        XCTAssertThrowsError(try MobilePersonaCardSnapshot(portrait: Data("not a picture".utf8), label: "", red: 0, green: 0, blue: 0))
    }
    func testInvalidStylesRejectedAndBlankLabelNormalizedBeforeRendering() throws {
        let portrait = try solidPortrait()
        let blank = try MobilePersonaCardSnapshot(portrait: portrait, label: "   ", red: 0, green: 0, blue: 0)
        XCTAssertEqual(blank.style.label, "")
        for label in [String(repeating: "x", count: 81), "Label\nOther line", "Hidden\0text"] {
            XCTAssertThrowsError(try MobilePersonaCardSnapshot(portrait: portrait, label: label, red: 0, green: 0, blue: 0))
        }
        for value in [Double.nan, Double.infinity, -0.1, 1.1] {
            XCTAssertThrowsError(try MobilePersonaCardSnapshot(portrait: portrait, label: "Fine", red: value, green: 0, blue: 0))
        }
    }
}
