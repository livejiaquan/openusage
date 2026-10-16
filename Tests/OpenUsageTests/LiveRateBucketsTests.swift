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

    func testMergeAfterClockRollbackKeepsEveryPart() {
        // A file's buckets were anchored before the clock stepped back 90 s; a newer file started after.
        var ahead = LiveRateBuckets(now: now)
        ahead.add(tokens: 600, at: now, now: now)
        let earlier = now.addingTimeInterval(-90)
        var fresh = LiveRateBuckets(now: earlier)
        fresh.add(tokens: 300, at: earlier, now: earlier)
        let merged = LiveRateBuckets.merged([ahead, fresh], now: earlier)
        XCTAssertEqual(merged.buckets.reduce(0, +), 900)
        XCTAssertEqual(merged.ratePerMinute(now: earlier), 180, accuracy: 0.001)
    }

    func testRemoveTakesBackTokensWithoutGoingNegative() {
        var buckets = LiveRateBuckets(now: now)
        buckets.add(tokens: 500, at: now.addingTimeInterval(-60), now: now)
        buckets.remove(tokens: 200, at: now.addingTimeInterval(-60), now: now)
        XCTAssertEqual(buckets.buckets.reduce(0, +), 300)
        buckets.remove(tokens: 900, at: now.addingTimeInterval(-60), now: now)
        XCTAssertEqual(buckets.buckets.reduce(0, +), 0)
    }

    func testSmoothedHistoryIsTheTrailingFiveMinuteRateAtEachPoint() {
        var buckets = LiveRateBuckets(now: now)
        buckets.add(tokens: 1_000, at: now, now: now)
        let smoothed = buckets.smoothedHistory(now: now)
        XCTAssertEqual(smoothed.count, 51)
        XCTAssertEqual(smoothed.last ?? -1, buckets.ratePerMinute(now: now), accuracy: 0.001)   // matches the headline
        XCTAssertEqual(smoothed.dropLast().reduce(0, +), 0, accuracy: 0.001)
    }

    func testSmoothedHistoryFlattensBursts() {
        // One 3,000-token burst every 90 s: raw buckets spike, the trailing rate stays level.
        var buckets = LiveRateBuckets(now: now)
        for step in 0..<20 { buckets.add(tokens: 3_000, at: now.addingTimeInterval(Double(-step) * 90), now: now) }
        let tail = buckets.smoothedHistory(now: now).suffix(30)
        let raw = buckets.history(now: now).suffix(30)
        XCTAssertGreaterThan(raw.max()! - raw.min()!, 5_000)
        XCTAssertLessThan(tail.max()! - tail.min()!, 700)
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
