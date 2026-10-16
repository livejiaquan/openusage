import XCTest
@testable import OpenUsage

/// The short pace phrase beside a meter's name, in the design's wording.
final class PaceLabelTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)
    private let week: TimeInterval = 7 * 24 * 60 * 60

    private func data(used: Double, elapsed: Double = 0.5, alwaysShowPacing: Bool = true) -> WidgetData {
        var data = WidgetData(title: "Weekly", icon: .providerMark("codex"), kind: .percent, used: used, limit: 100)
        data.resetsAt = now.addingTimeInterval(week * (1 - elapsed))
        data.periodDurationMs = Int(week * 1000)
        data.alwaysShowPacing = alwaysShowPacing
        return data
    }

    private func label(_ data: WidgetData) -> PaceLabel? {
        data.paceLabel(for: data.meterState(now: now), now: now)
    }

    func testHealthyMeterReadsOnPace() {
        XCTAssertEqual(label(data(used: 20)), PaceLabel(text: "on pace", isWarning: false))
    }

    func testHealthyMeterIsSilentWhenPacingIsHidden() {
        XCTAssertNil(label(data(used: 20, alwaysShowPacing: false)))
    }

    func testRunningOutReadsEmptyInWithTheRunOutTime() throws {
        let running = data(used: 80)
        let seconds = try XCTUnwrap(running.secondsToRunOut(now: now))
        let expected = "empty in ~" + (Formatters.compactDuration(seconds) ?? "")
        XCTAssertEqual(label(running), PaceLabel(text: expected, isWarning: true))
    }

    func testCloseToLimitKeepsTheSpareCushion() {
        XCTAssertEqual(label(data(used: 46)), PaceLabel(text: "~8% spare", isWarning: false))
    }

    func testSpentReadsLimitReached() {
        XCTAssertEqual(label(data(used: 100)), PaceLabel(text: "Limit reached", isWarning: true))
    }

    func testNoDataHasNoLabel() {
        var empty = data(used: 0)
        empty.hasData = false
        XCTAssertNil(label(empty))
    }
}
