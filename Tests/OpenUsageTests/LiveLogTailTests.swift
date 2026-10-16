import XCTest
@testable import OpenUsage

final class LiveLogTailTests: XCTestCase {
    private var dir: URL!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("live-tail-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dir)
    }

    private func claudeLine(id: String, request: String, input: Int, output: Int = 0, at date: Date,
                            sidechain: Bool = false) -> String {
        let stamp = OpenUsageISO8601.string(from: date)
        return #"{"timestamp":"\#(stamp)","isSidechain":\#(sidechain),"sessionId":"s","requestId":"\#(request)","version":"2.1.0","message":{"id":"\#(id)","model":"claude-test-model","usage":{"input_tokens":\#(input),"output_tokens":\#(output)}}}"#
    }

    private func write(_ name: String, _ text: String) throws -> URL {
        let url = dir.appendingPathComponent(name)
        try text.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    private func append(_ url: URL, _ text: String) throws {
        let handle = try FileHandle(forWritingTo: url)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data(text.utf8))
        try handle.close()
    }

    private func tail(_ family: LiveFamily, _ urls: [URL]) -> LiveLogTail {
        LiveLogTail(family: family, candidateFiles: { _ in urls })
    }

    func testAppendedClaudeLinesRaiseRate() async throws {
        let now = Date()
        let url = try write("a.jsonl", claudeLine(id: "m1", request: "r1", input: 1_000, at: now.addingTimeInterval(-60)) + "\n")
        let tail = tail(.claude, [url])
        let first = await tail.poll(now: now)
        XCTAssertEqual(first.ratePerMinute(now: now), 200, accuracy: 0.001)

        try append(url, claudeLine(id: "m2", request: "r2", input: 500, at: now.addingTimeInterval(-30)) + "\n")
        let second = await tail.poll(now: now)
        XCTAssertEqual(second.ratePerMinute(now: now), 300, accuracy: 0.001)
    }

    func testDuplicateClaudeMessageCountsOnce() async throws {
        let now = Date()
        let line = claudeLine(id: "m1", request: "r1", input: 1_000, at: now.addingTimeInterval(-60)) + "\n"
        let a = try write("a.jsonl", line)
        let b = try write("b.jsonl", line)
        let buckets = await tail(.claude, [a, b]).poll(now: now)
        XCTAssertEqual(buckets.ratePerMinute(now: now), 200, accuracy: 0.001)
    }

    func testLargerDuplicateReplacesTheSmallerOne() async throws {
        let now = Date()
        let url = try write("a.jsonl", claudeLine(id: "m1", request: "r1", input: 100, at: now.addingTimeInterval(-60)) + "\n")
        let tail = tail(.claude, [url])
        _ = await tail.poll(now: now)
        try append(url, claudeLine(id: "m1", request: "r1", input: 500, at: now.addingTimeInterval(-60)) + "\n")
        let buckets = await tail.poll(now: now)
        XCTAssertEqual(buckets.ratePerMinute(now: now), 100, accuracy: 0.001)   // 500 tokens over 5 minutes
    }

    func testLargerDuplicateInAnotherFileMovesTheCount() async throws {
        let now = Date()
        let a = try write("a.jsonl", claudeLine(id: "m1", request: "r1", input: 100, at: now.addingTimeInterval(-60)) + "\n")
        let b = try write("b.jsonl", claudeLine(id: "m1", request: "r1", input: 500, at: now.addingTimeInterval(-60)) + "\n")
        let buckets = await tail(.claude, [a, b]).poll(now: now)
        XCTAssertEqual(buckets.ratePerMinute(now: now), 100, accuracy: 0.001)
    }

    func testSidechainReplayUnderANewRequestIsNotCounted() async throws {
        let now = Date()
        let parent = claudeLine(id: "m1", request: "r1", input: 1_000, at: now.addingTimeInterval(-60))
        let replay = claudeLine(id: "m1", request: "r2", input: 1_000, at: now.addingTimeInterval(-50), sidechain: true)
        let url = try write("a.jsonl", parent + "\n" + replay + "\n")
        let buckets = await tail(.claude, [url]).poll(now: now)
        XCTAssertEqual(buckets.ratePerMinute(now: now), 200, accuracy: 0.001)
    }

    func testCodexTokenCountsUseParserDeltas() async throws {
        let now = Date()
        let lines = [
            CodexLogFixture.turnContext(timestamp: OpenUsageISO8601.string(from: now.addingTimeInterval(-120)), model: "gpt-5.2"),
            CodexLogFixture.tokenCount(timestamp: OpenUsageISO8601.string(from: now.addingTimeInterval(-90)),
                                       totals: ["input_tokens": 100, "output_tokens": 20, "total_tokens": 120]),
            CodexLogFixture.tokenCount(timestamp: OpenUsageISO8601.string(from: now.addingTimeInterval(-60)),
                                       totals: ["input_tokens": 150, "output_tokens": 30, "total_tokens": 180]),
        ].joined(separator: "\n") + "\n"
        let url = try write("rollout.jsonl", lines)
        let expected = CodexLogUsageScanner.parseFile(Data(lines.utf8)).map(\.total).reduce(0, +)
        XCTAssertEqual(expected, 180, "the parser reports the first total, then only the delta")
        let buckets = await tail(.codex, [url]).poll(now: now)
        XCTAssertEqual(buckets.ratePerMinute(now: now), Double(expected) / 5, accuracy: 0.001)
    }

    func testPartialLineIsReadOnceComplete() async throws {
        let now = Date()
        let url = try write("a.jsonl", claudeLine(id: "m1", request: "r1", input: 1_000, at: now.addingTimeInterval(-60)))
        let tail = tail(.claude, [url])
        let before = await tail.poll(now: now)
        XCTAssertEqual(before.ratePerMinute(now: now), 0, accuracy: 0.001)

        try append(url, "\n")
        let after = await tail.poll(now: now)
        XCTAssertEqual(after.ratePerMinute(now: now), 200, accuracy: 0.001)
    }

    func testTruncatedFileRestartsWithoutDoubleCounting() async throws {
        let now = Date()
        let first = claudeLine(id: "m1", request: "r1", input: 1_000, at: now.addingTimeInterval(-60)) + "\n"
        let second = claudeLine(id: "m2", request: "r2", input: 1_000, at: now.addingTimeInterval(-50)) + "\n"
        let url = try write("a.jsonl", first + second)
        let tail = tail(.claude, [url])
        let full = await tail.poll(now: now)
        XCTAssertEqual(full.ratePerMinute(now: now), 400, accuracy: 0.001)

        _ = try write("a.jsonl", first)
        let rewritten = await tail.poll(now: now)
        XCTAssertEqual(rewritten.ratePerMinute(now: now), 200, accuracy: 0.001)
    }

    func testFilesOlderThanThirtyMinutesAreNotRead() async {
        let now = Date()
        let asked = DateBox()
        let tail = LiveLogTail(family: .claude, candidateFiles: { since in
            asked.value = since
            return []
        })
        _ = await tail.poll(now: now)
        XCTAssertEqual(asked.value?.timeIntervalSince(now) ?? 0, -30 * 60, accuracy: 0.001)
    }
}

private final class DateBox: @unchecked Sendable {
    var value: Date?
}
