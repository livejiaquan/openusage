import XCTest
@testable import OpenUsage

final class CalmMeterSweepTests: XCTestCase {
    func testNoSweepWithoutActivity() {
        XCTAssertNil(CalmMeterSweep.period(forRate: 0))
        XCTAssertNil(CalmMeterSweep.period(forRate: -5))
    }

    func testPeriodClampsBetweenEightAndSixteen() {
        XCTAssertEqual(CalmMeterSweep.period(forRate: 1) ?? 0, 16, accuracy: 0.01)
        XCTAssertEqual(CalmMeterSweep.period(forRate: 750_000) ?? 0, 12, accuracy: 0.01)
        XCTAssertEqual(CalmMeterSweep.period(forRate: 1_500_000) ?? 0, 8, accuracy: 0.01)
        XCTAssertEqual(CalmMeterSweep.period(forRate: 9_000_000) ?? 0, 8, accuracy: 0.01)
    }
}
