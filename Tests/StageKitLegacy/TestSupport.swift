// A dependency-free assertion runner so tests work with Apple Command Line Tools.
// XCTest ships with full Xcode and is not present on every Mac.
import Foundation

class XCTestCase {}
var assertionFailures = 0
var assertionCount = 0
func check(_ passed: Bool, _ message: String, file: StaticString, line: UInt) {
    assertionCount += 1
    if !passed { assertionFailures += 1; print("FAIL \(file):\(line): \(message)") }
}
func XCTAssertTrue(_ value: @autoclosure () throws -> Bool, _ message: String = "Expected true", file: StaticString = #filePath, line: UInt = #line) {
    do { check(try value(), message, file: file, line: line) }
    catch { check(false, error.localizedDescription, file: file, line: line) }
}
func XCTAssertFalse(_ value: @autoclosure () -> Bool, _ message: String = "Expected false", file: StaticString = #filePath, line: UInt = #line) {
    check(!value(), message, file: file, line: line)
}
func XCTAssertEqual<T: Equatable>(_ a: @autoclosure () throws -> T, _ b: @autoclosure () throws -> T, _ message: String = "Values differ", file: StaticString = #filePath, line: UInt = #line) {
    do { let first = try a(), second = try b(); check(first == second, "\(message): \(first) != \(second)", file: file, line: line) }
    catch { check(false, error.localizedDescription, file: file, line: line) }
}
func XCTAssertEqual(_ a: Double, _ b: Double, accuracy: Double, file: StaticString = #filePath, line: UInt = #line) {
    check(abs(a - b) <= accuracy, "\(a) != \(b) ± \(accuracy)", file: file, line: line)
}
func XCTAssertGreaterThan<T: Comparable>(_ a: T, _ b: T, _ message: String = "Expected a greater value", file: StaticString = #filePath, line: UInt = #line) {
    check(a > b, message, file: file, line: line)
}
func XCTAssertNotNil<T>(_ value: T?, file: StaticString = #filePath, line: UInt = #line) {
    check(value != nil, "Expected a value", file: file, line: line)
}
func XCTAssertThrowsError<T>(_ expression: @autoclosure () throws -> T, file: StaticString = #filePath, line: UInt = #line) {
    do { _ = try expression(); check(false, "Expected an error", file: file, line: line) }
    catch { check(true, "", file: file, line: line) }
}
