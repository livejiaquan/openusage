import XCTest
@testable import OpenUsage

final class LiveRateBucketsTests: XCTestCase {
    private let now = Date(timeIntervalSinceReferenceDate: 800_000_000)

    func testRateCountsOnlyTrailingFiveMinutes() {
        var buckets = LiveRateBuckets(now: now)
        buckets.add(tokens: 1_000, at: now.addingTimeInterval(-60), now: now)
        buckets.add(tokens: 9_000, at: now.addingTimeInterval(-600), now: now)
        XCTAssertEqual(buckets.ratePerMinute(now: now), 200, accuracy: 0.001)
    }

    func testHistoryHasSixtyBucketsInTokensPerMinute() {
        var buckets = LiveRateBuckets(now: now)
        buckets.add(tokens: 300, at: now.addingTimeInterval(-15), now: now)
        let history = buckets.history(now: now)
        XCTAssertEqual(history.count, 60)
        XCTAssertEqual(history.last ?? -1, 600, accuracy: 0.001)
        XCTAssertEqual(history.dropLast().reduce(0, +), 0, accuracy: 0.001)
    }

    func testLongGapClearsBuckets() {
        var buckets = LiveRateBuckets(now: now)
        buckets.add(tokens: 5_000, at: now.addingTimeInterval(-30), now: now)
        let later = now.addingTimeInterval(2 * 3_600)
        buckets.advance(to: later)
        XCTAssertEqual(buckets.history(now: later).reduce(0, +), 0, accuracy: 0.001)
        XCTAssertEqual(buckets.ratePerMinute(now: later), 0, accuracy: 0.001)
    }

    func testAdvancingKeepsRecentBucketsAndShiftsThem() {
        var buckets = LiveRateBuckets(now: now)
        buckets.add(tokens: 300, at: now.addingTimeInterval(-15), now: now)
        let later = now.addingTimeInterval(60)
        buckets.advance(to: later)
        let history = buckets.history(now: later)
        XCTAssertEqual(history.reduce(0, +), 600, accuracy: 0.001)
        XCTAssertEqual(history.last ?? -1, 0, accuracy: 0.001)
    }

    func testEventsBeyondWindowAreIgnored() {
        var buckets = LiveRateBuckets(now: now)
        buckets.add(tokens: 1_000, at: now.addingTimeInterval(-31 * 60), now: now)
        buckets.add(tokens: 1_000, at: now.addingTimeInterval(5 * 60), now: now)
        XCTAssertEqual(buckets, LiveRateBuckets(now: now))
    }

    func testMergedSumsBucketwise() {
        var a = LiveRateBuckets(now: now)
        var b = LiveRateBuckets(now: now)
        a.add(tokens: 100, at: now.addingTimeInterval(-20), now: now)
        b.add(tokens: 50, at: now.addingTimeInterval(-20), now: now)
        b.add(tokens: 70, at: now.addingTimeInterval(-200), now: now)
        let merged = LiveRateBuckets.merged([a, b], now: now)
        XCTAssertEqual(merged.ratePerMinute(now: now), 44, accuracy: 0.001)   // 220 tokens / 5 min
        XCTAssertEqual(merged.history(now: now).last ?? -1, 300, accuracy: 0.001)
    }
}
