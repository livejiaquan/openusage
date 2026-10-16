import Foundation

enum LiveFamily: String, Sendable, CaseIterable {
    case claude, codex
}

/// Live token speed from this Mac's recent Claude or Codex session logs. Each poll looks only at files
/// modified in the last 30 minutes and reads only bytes appended since the previous poll, parsing
/// complete lines with the same parsers the daily history uses, so live and daily counts agree.
///
/// Every file keeps its own buckets: when a file shrinks (rewritten or truncated) only that file's
/// contribution is dropped and re-read, which keeps a rewrite from double counting.
actor LiveLogTail {
    static let window: TimeInterval = 30 * 60

    private struct Cursor {
        var offset: UInt64 = 0
        var buckets: LiveRateBuckets
        /// Codex rollouts are stateful (model, cumulative totals, replay gates), so the parser travels
        /// with the file's cursor.
        var codexParser: CodexLogFileParser?
    }

    private let family: LiveFamily
    private let candidateFiles: @Sendable (_ modifiedSince: Date) async -> [URL]
    private var cursors: [String: Cursor] = [:]
    /// Claude dedup across files: "messageID|requestID" → owning file and event time.
    private var claudeKeys: [String: (path: String, timestamp: Date)] = [:]

    init(family: LiveFamily, candidateFiles: @escaping @Sendable (_ modifiedSince: Date) async -> [URL]) {
        self.family = family
        self.candidateFiles = candidateFiles
    }

    func poll(now: Date) async -> LiveRateBuckets {
        let files = await candidateFiles(now.addingTimeInterval(-Self.window))
        let current = Set(files.map(\.path))
        for path in cursors.keys where !current.contains(path) { forget(path) }
        for url in files { read(url, now: now) }
        claudeKeys = claudeKeys.filter { now.timeIntervalSince($0.value.timestamp) <= Self.window }
        return LiveRateBuckets.merged(cursors.values.map(\.buckets), now: now)
    }

    func reset() {
        cursors = [:]
        claudeKeys = [:]
    }

    private func newCursor(now: Date) -> Cursor {
        Cursor(buckets: LiveRateBuckets(now: now), codexParser: family == .codex ? CodexLogFileParser() : nil)
    }

    private func forget(_ path: String) {
        cursors[path] = nil
        claudeKeys = claudeKeys.filter { $0.value.path != path }
    }

    private func read(_ url: URL, now: Date) {
        let path = url.path
        guard let handle = try? FileHandle(forReadingFrom: url) else { return }
        defer { try? handle.close() }
        guard let size = try? handle.seekToEnd() else { return }

        if let existing = cursors[path], size < existing.offset { forget(path) }
        var cursor = cursors[path] ?? newCursor(now: now)
        guard size > cursor.offset else {
            cursors[path] = cursor
            return
        }
        try? handle.seek(toOffset: cursor.offset)
        guard let data = try? handle.read(upToCount: Int(size - cursor.offset)),
              let lastNewline = data.lastIndex(of: UInt8(ascii: "\n"))
        else {
            cursors[path] = cursor   // only a partial line so far; read it once it is complete
            return
        }
        let complete = Data(data[data.startIndex...lastNewline])
        cursor.offset += UInt64(complete.count)

        switch family {
        case .claude:
            for entry in ClaudeLogUsageScanner.parseFile(complete) {
                if let messageID = entry.messageID {
                    let key = "\(messageID)|\(entry.requestID ?? "")"
                    guard claudeKeys[key] == nil else { continue }
                    claudeKeys[key] = (path, entry.timestamp)
                }
                cursor.buckets.add(tokens: entry.tokens.totalTokens, at: entry.timestamp, now: now)
            }
        case .codex:
            var parser = cursor.codexParser ?? CodexLogFileParser()
            for event in parser.parse(complete) {
                cursor.buckets.add(tokens: event.total, at: event.timestamp, now: now)
            }
            cursor.codexParser = parser
        }
        cursors[path] = cursor
    }
}
