import XCTest
@testable import OpenUsage

final class TopModelsTests: XCTestCase {
    private func breakdown(_ models: [(String, Int, Double?)]) -> ModelUsageBreakdown {
        ModelUsageBreakdown(totalTokens: models.map(\.1).reduce(0, +), totalCostUSD: nil,
                            models: models.map { ModelUsageEntry(model: $0.0, totalTokens: $0.1, costUSD: $0.2) },
                            sourceNote: "logs")
    }

    func testTopThreeByCostWithShares() {
        let entries = TopModels.entries(from: breakdown([("haiku", 900, 10), ("opus", 100, 60), ("sonnet", 500, 25), ("fable", 50, 5)]))
        XCTAssertEqual(entries.map(\.model), ["opus", "sonnet", "haiku"])
        XCTAssertEqual(entries[0].share, 0.6, accuracy: 0.0001)
        XCTAssertEqual(entries[0].cost, 60, accuracy: 0.0001)
    }

    func testUnpricedModelsRankByTokens() {
        let entries = TopModels.entries(from: breakdown([("a", 100, nil), ("b", 300, nil)]))
        XCTAssertEqual(entries.map(\.model), ["b", "a"])
        XCTAssertEqual(entries[0].share, 0.75, accuracy: 0.0001)
    }

    func testOneModelHidesRow() {
        XCTAssertTrue(TopModels.entries(from: breakdown([("opus", 100, 60)])).isEmpty)
        XCTAssertTrue(TopModels.entries(from: nil).isEmpty)
    }

    func testTopModelsIsNotPinnableAndOnDemandByDefault() {
        let provider = Provider(id: "claude", displayName: "Claude", icon: .providerMark("claude"))
        let descriptor = WidgetDescriptor.topModelsToday(provider: provider)
        XCTAssertEqual(descriptor.id, "claude.topModels")
        XCTAssertEqual(descriptor.metricLabel, "Today")
        XCTAssertFalse(descriptor.pinnable)
        XCTAssertTrue(descriptor.sample.showsTopModels)
        XCTAssertTrue(DefaultLayout.metricIDs.contains("claude.topModels"))
        XCTAssertTrue(DefaultLayout.expandedMetricIDs.contains("claude.topModels"))
        XCTAssertFalse(DefaultLayout.pinnedMetricIDs.contains("claude.topModels"))
    }
}
