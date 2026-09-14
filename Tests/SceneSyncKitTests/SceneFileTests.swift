import Foundation
import XCTest
@testable import SceneSyncKit

final class SceneFileTests: XCTestCase {
    func testExplicitFileReadIsBoundedAndDoesNotModifySource() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("example.workbenchscene")
        let bytes = Data("A malformed scene stays a harmless copy.".utf8)
        try bytes.write(to: file)
        XCTAssertEqual(try SceneFile.read(file), bytes)
        XCTAssertThrowsError(try ScenePackage.decode(SceneFile.read(file)))
        XCTAssertEqual(try Data(contentsOf: file), bytes)
        XCTAssertThrowsError(try SceneFile.read(root))
        try Data().write(to: file)
        XCTAssertThrowsError(try SceneFile.read(file))
        let handle = try FileHandle(forWritingTo: file)
        try handle.truncate(atOffset: UInt64(ScenePackage.maximumBytes + 1))
        try handle.close()
        XCTAssertThrowsError(try SceneFile.read(file))
        XCTAssertEqual((try FileManager.default.attributesOfItem(atPath: file.path)[.size] as? NSNumber)?.intValue, ScenePackage.maximumBytes + 1)
    }
}
