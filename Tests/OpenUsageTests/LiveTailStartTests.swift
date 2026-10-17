import XCTest
@testable import OpenUsage

/// A newly tracked Claude log is read from where its last 30 minutes begin, not from its first byte, so
/// opening the panel next to a long session doesn't parse tens of megabytes.
final class LiveTailStartTests: XCTestCase {
    private let now = Date(timeIntervalSinceReferenceDate: 800_000_000)

    private func line(_ date: Date, padding: Int = 200) -> String {
        #"{"timestamp":"\#(OpenUsageISO8601.string(from: date))","pad":"\#(String(repeating: "x", count: padding))"}"#
    }

    private func start(of data: Data, since: Date, step: UInt64 = 1_024) -> UInt64 {
        LiveTailStart.offset(size: UInt64(data.count), since: since, initialStep: step) { offset, count in
            let lower = Int(offset), upper = min(Int(offset) + count, data.count)
            return lower < upper ? data.subdata(in: lower..<upper) : nil
        }
    }

    func testSkipsOldLinesAndLandsOnALineStart() throws {
        let old = (0..<200).map { line(now.addingTimeInterval(-7_200 + Double($0))) }
        let recent = (0..<5).map { line(now.addingTimeInterval(-60 + Double($0))) }
        let text = (old + recent).joined(separator: "\n") + "\n"
        let data = Data(text.utf8)
        let recentStart = UInt64(Data((old.joined(separator: "\n") + "\n").utf8).count)

        let offset = start(of: data, since: now.addingTimeInterval(-1_800))
        XCTAssertGreaterThan(offset, 0, "old history is skipped")
        XCTAssertLessThanOrEqual(offset, recentStart, "nothing inside the window is skipped")
        XCTAssertEqual(data[Int(offset)], UInt8(ascii: "{"), "starts on a whole line")
    }

    func testAllRecentFileIsReadFromTheStart() {
        let text = (0..<50).map { line(now.addingTimeInterval(-60 + Double($0))) }.joined(separator: "\n") + "\n"
        XCTAssertEqual(start(of: Data(text.utf8), since: now.addingTimeInterval(-1_800)), 0)
    }

    func testSmallFileIsReadFromTheStart() {
        let text = line(now.addingTimeInterval(-7_200)) + "\n" + line(now) + "\n"
        XCTAssertEqual(start(of: Data(text.utf8), since: now.addingTimeInterval(-1_800)), 0)
    }
}
