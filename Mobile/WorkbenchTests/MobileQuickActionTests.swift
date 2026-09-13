import XCTest
@testable import WorkbenchMobile

@MainActor final class MobileQuickActionTests: XCTestCase {
    func testUnknownActionDoesNotReplacePendingIntent() {
        let router = MobileQuickActionRouter()
        XCTAssertTrue(router.receive(type: MobileQuickAction.captureScene.rawValue))
        XCTAssertFalse(router.receive(type: "unrelated.action"))
        XCTAssertEqual(router.take(isActive: true), .captureScene)
    }
    func testBackgroundDeliveryWaitsAndForegroundConsumesOnlyOnce() {
        let router = MobileQuickActionRouter()
        XCTAssertTrue(router.receive(type: MobileQuickAction.dictate.rawValue))
        XCTAssertNil(router.take(isActive: false))
        XCTAssertEqual(router.pending, .dictate)
        XCTAssertEqual(router.take(isActive: true), .dictate)
        XCTAssertNil(router.take(isActive: true))
    }
    func testLatestExplicitActionSupersedesEarlierUnconsumedAction() {
        let router = MobileQuickActionRouter()
        _ = router.receive(type: MobileQuickAction.dictate.rawValue)
        _ = router.receive(type: MobileQuickAction.captureScene.rawValue)
        XCTAssertEqual(router.take(isActive: true), .captureScene)
    }
}
