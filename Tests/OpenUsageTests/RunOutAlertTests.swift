import XCTest
@testable import OpenUsage

final class RunOutAlertTests: XCTestCase {
    private let now = Date(timeIntervalSinceReferenceDate: 800_000_000)
    private let period: TimeInterval = 5 * 3_600

    /// A 5-hour window that started `elapsed` seconds ago with `used` of 100 spent.
    private func meter(_ title: String = "Session", used: Double, elapsed: TimeInterval) -> WidgetData {
        var data = WidgetData(title: title, icon: .providerMark("claude"), kind: .percent, used: used, limit: 100)
        data.resetsAt = now.addingTimeInterval(period - elapsed)
        data.periodDurationMs = Int(period * 1_000)
        return data
    }

    func testHealthyMeterHasNoAlert() {
        let data = meter(used: 10, elapsed: 3_600)
        XCTAssertNil(data.runOutLeadTime(now: now))
        XCTAssertNil(RunOutAlert.soonest([("Claude", data)], now: now))
    }

    func testRunningOutMeterReportsLeadTime() throws {
        let data = meter(used: 60, elapsed: 3_600)
        let toRunOut = try XCTUnwrap(data.secondsToRunOut(now: now))
        let lead = try XCTUnwrap(data.runOutLeadTime(now: now))
        XCTAssertEqual(lead, data.resetsAt!.timeIntervalSince(now.addingTimeInterval(toRunOut)), accuracy: 1)
        XCTAssertGreaterThan(lead, 0)

        let alert = try XCTUnwrap(RunOutAlert.soonest([("Claude", data)], now: now))
        XCTAssertEqual(alert.providerName, "Claude")
        XCTAssertEqual(alert.metricTitle, "Session")
        XCTAssertTrue(alert.message.hasPrefix("Session runs out about "))
        XCTAssertTrue(alert.message.hasSuffix(" before it resets at this pace."))
    }

    func testSoonestRunOutWins() throws {
        let slower = meter("Weekly", used: 30, elapsed: 3_600)    // runs out later
        let faster = meter("Session", used: 70, elapsed: 3_600)   // runs out sooner
        XCTAssertNotNil(slower.secondsToRunOut(now: now))
        let alert = try XCTUnwrap(RunOutAlert.soonest([("Codex", slower), ("Claude", faster)], now: now))
        XCTAssertEqual(alert.providerName, "Claude")
        XCTAssertEqual(alert.metricTitle, "Session")
    }

    @MainActor
    func testDisabledProviderNeverAlerts() throws {
        let suite = "RunOutAlertTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let provider = Provider(id: "claude", displayName: "Claude", icon: .providerMark("claude"))
        let descriptor = WidgetDescriptor.percent(id: "claude.session", provider: provider, title: "Session")
        let registry = WidgetRegistry(providers: [provider], descriptors: [descriptor])
        let cache = ProviderSnapshotCache(userDefaults: defaults, storageKey: "snapshots")
        let store = WidgetDataStore(registry: registry, providers: [], cache: cache, defaults: defaults,
                                    isProviderEnabled: { _ in false })
        XCTAssertNil(store.runOutAlert(now: now))
    }
}
