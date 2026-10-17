import XCTest
@testable import OpenUsage

/// The live tail can start a big Codex rollout partway through (its last half hour). The parser then has
/// no running total yet, so a totals-only line must seed the baseline instead of counting the whole
/// session as one turn.
final class CodexMidFileParserTests: XCTestCase {
    private func data(_ lines: [String]) -> Data { Data((lines.joined(separator: "\n") + "\n").utf8) }

    func testTotalsOnlyFirstLineSeedsTheBaselineMidFile() {
        var parser = CodexLogFileParser()
        parser.resumeMidFile()
        let events = parser.parse(data([
            CodexLogFixture.tokenCount(timestamp: "2026-10-17T02:00:00Z",
                                       totals: CodexLogFixture.usage(input: 9_000, output: 1_000)),
            CodexLogFixture.tokenCount(timestamp: "2026-10-17T02:01:00Z",
                                       totals: CodexLogFixture.usage(input: 10_500, output: 1_500)),
        ]))
        XCTAssertEqual(events.map(\.total), [2_000])
    }

    func testTurnDeltaStillCountsWhenResumingMidFile() {
        var parser = CodexLogFileParser()
        parser.resumeMidFile()
        let events = parser.parse(data([
            CodexLogFixture.tokenCount(timestamp: "2026-10-17T02:00:00Z",
                                       last: CodexLogFixture.usage(input: 400, output: 100),
                                       totals: CodexLogFixture.usage(input: 9_000, output: 1_000)),
        ]))
        XCTAssertEqual(events.map(\.total), [500])
    }

    func testFromTheStartAFirstTotalsLineCountsInFull() {
        var parser = CodexLogFileParser()
        let events = parser.parse(data([
            CodexLogFixture.tokenCount(timestamp: "2026-10-17T02:00:00Z",
                                       totals: CodexLogFixture.usage(input: 900, output: 100)),
        ]))
        XCTAssertEqual(events.map(\.total), [1_000])
    }
}
