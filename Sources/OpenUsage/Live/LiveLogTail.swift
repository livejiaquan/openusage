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
    /// Claude dedup across files with the history scanner's rules (`ClaudeLogUsageScanner.dedup`):
    /// "messageID|requestID" → the kept entry and the file that counted it, plus a message-only index
    /// so a sidechain replay under a new request id collides too. A preferred duplicate (parent over
    /// sidechain, then more tokens) takes the kept entry's tokens back and counts its own.
    private var claudeKept: [String: (path: String, entry: ClaudeLogUsageScanner.Entry)] = [:]
    private var claudeKeysByMessage: [String: Set<String>] = [:]

    init(family: LiveFamily, candidateFiles: @escaping @Sendable (_ modifiedSince: Date) async -> [URL]) {
        self.family = family
        self.candidateFiles = candidateFiles
    }

    func poll(now: Date) async -> LiveRateBuckets {
        let files = await candidateFiles(now.addingTimeInterval(-Self.window))
        let current = Set(files.map(\.path))
        for path in cursors.keys where !current.contains(path) { forget(path) }
        for url in files { read(url, now: now) }
        dropClaudeKeys { now.timeIntervalSince($0.entry.timestamp) > Self.window }
        return LiveRateBuckets.merged(cursors.values.map(\.buckets), now: now)
    }

    func reset() {
        cursors = [:]
        claudeKept = [:]
        claudeKeysByMessage = [:]
    }

    private func newCursor(now: Date) -> Cursor {
        Cursor(buckets: LiveRateBuckets(now: now), codexParser: family == .codex ? CodexLogFileParser() : nil)
    }

    private func forget(_ path: String) {
        cursors[path] = nil
        dropClaudeKeys { $0.path == path }
    }

    private func dropClaudeKeys(where shouldDrop: ((path: String, entry: ClaudeLogUsageScanner.Entry)) -> Bool) {
        for (key, kept) in claudeKept where shouldDrop(kept) {
            claudeKept[key] = nil
            if let messageID = kept.entry.messageID {
                claudeKeysByMessage[messageID]?.remove(key)
                if claudeKeysByMessage[messageID]?.isEmpty == true { claudeKeysByMessage[messageID] = nil }
            }
        }
    }

    /// Applies the history scanner's dedup to one new Claude entry against everything kept so far.
    private func count(_ entry: ClaudeLogUsageScanner.Entry, path: String, cursor: inout Cursor, now: Date) {
        guard let messageID = entry.messageID else {
            cursor.buckets.add(tokens: entry.tokens.totalTokens, at: entry.timestamp, now: now)
            return
        }
        let key = "\(messageID)|\(entry.requestID ?? "")"
        let collision: String? = claudeKept[key] != nil ? key : claudeKeysByMessage[messageID]?.first(where: { other in
            entry.isSidechain || claudeKept[other]?.entry.isSidechain == true
        })
        if let collision, let kept = claudeKept[collision] {
            guard ClaudeLogUsageScanner.shouldReplace(candidate: entry, existing: kept.entry) else { return }
            let old = kept.entry
            if kept.path == path {
                cursor.buckets.remove(tokens: old.tokens.totalTokens, at: old.timestamp, now: now)
            } else {
                cursors[kept.path]?.buckets.remove(tokens: old.tokens.totalTokens, at: old.timestamp, now: now)
            }
            claudeKept[collision] = nil
            claudeKeysByMessage[messageID]?.remove(collision)
        }
        claudeKept[key] = (path, entry)
        claudeKeysByMessage[messageID, default: []].insert(key)
        cursor.buckets.add(tokens: entry.tokens.totalTokens, at: entry.timestamp, now: now)
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
                count(entry, path: path, cursor: &cursor, now: now)
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
