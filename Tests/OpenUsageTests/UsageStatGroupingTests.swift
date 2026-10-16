import XCTest
@testable import OpenUsage

final class UsageStatGroupingTests: XCTestCase {
    func testThreeAdjacentStatsMerge() {
        XCTAssertEqual(UsageStatGrouping.group(["claude.session", "claude.today", "claude.yesterday", "claude.last30", "claude.trend"]),
                       [.single("claude.session"), .usageStats(["claude.today", "claude.yesterday", "claude.last30"]), .single("claude.trend")])
    }

    func testTwoAdjacentStatsMerge() {
        XCTAssertEqual(UsageStatGrouping.group(["codex.yesterday", "codex.last30"]),
                       [.usageStats(["codex.yesterday", "codex.last30"])])
    }

    func testSingleStatStaysSingle() {
        XCTAssertEqual(UsageStatGrouping.group(["claude.session", "claude.today", "claude.trend"]),
                       [.single("claude.session"), .single("claude.today"), .single("claude.trend")])
    }

    func testNonAdjacentStatsDoNotMerge() {
        XCTAssertEqual(UsageStatGrouping.group(["claude.today", "claude.trend", "claude.yesterday"]),
                       [.single("claude.today"), .single("claude.trend"), .single("claude.yesterday")])
    }

    func testStatSuffixMatchesAccountCardsAndExactSuffixOnly() {
        XCTAssertTrue(UsageStatGrouping.isStat("claude@aaaa1111.today"))
        XCTAssertFalse(UsageStatGrouping.isStat("claude.todayish"))
    }
}
