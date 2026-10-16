import XCTest
@testable import OpenUsage

final class ResetListLayoutTests: XCTestCase {
    private let now = Date(timeIntervalSinceReferenceDate: 800_000_000)

    func testTwoOrFewerShowAll() {
        XCTAssertTrue(ResetListLayout.visible(total: 0, expanded: false) == (0, 0))
        XCTAssertTrue(ResetListLayout.visible(total: 1, expanded: false) == (1, 0))
        XCTAssertTrue(ResetListLayout.visible(total: 2, expanded: false) == (2, 0))
    }

    func testFiveCollapsedShowsTwoHidesThree() {
        XCTAssertTrue(ResetListLayout.visible(total: 5, expanded: false) == (2, 3))
    }

    func testExpandedShowsAll() {
        XCTAssertTrue(ResetListLayout.visible(total: 5, expanded: true) == (5, 0))
    }

    func testSoonIsWithinThreeDays() {
        XCTAssertTrue(ResetListLayout.isSoon(now.addingTimeInterval(2 * 86_400), now: now))
        XCTAssertTrue(ResetListLayout.isSoon(now.addingTimeInterval(3 * 86_400), now: now))
        XCTAssertFalse(ResetListLayout.isSoon(now.addingTimeInterval(3 * 86_400 + 60), now: now))
    }

    func testCountdownUsesTheLargestUnit() {
        XCTAssertEqual(ResetListLayout.countdown(to: now.addingTimeInterval(3 * 86_400 + 3_600), now: now), "in 3d")
        XCTAssertEqual(ResetListLayout.countdown(to: now.addingTimeInterval(5 * 3_600), now: now), "in 5h")
        XCTAssertEqual(ResetListLayout.countdown(to: now.addingTimeInterval(20 * 60), now: now), "in 20m")
        XCTAssertEqual(ResetListLayout.countdown(to: now.addingTimeInterval(-60), now: now), "now")
    }
}
