import Foundation

/// Where a newly tracked Claude log's recent window begins, so the live tail reads only the last half
/// hour of a long session instead of parsing it from its first byte (a busy Claude session log is tens of
/// megabytes, and re-reading it made opening the panel stutter). Lines are appended in time order, so
/// probing backwards from the end in doubling steps until a line older than `since` finds a safe start.
/// Falls back to 0 (read everything) for small files, all-recent files, or lines it can't date.
enum LiveTailStart {
    static func offset(size: UInt64, since: Date, initialStep: UInt64 = 512 * 1024, probeLength: Int = 64 * 1024,
                       read: (_ offset: UInt64, _ count: Int) -> Data?) -> UInt64 {
        var step = initialStep
        while step < size {
            let probe = size - step
            if let chunk = read(probe, probeLength), let newline = chunk.firstIndex(of: UInt8(ascii: "\n")) {
                let lineStart = chunk.index(after: newline)
                if let end = chunk[lineStart...].firstIndex(of: UInt8(ascii: "\n")),
                   let stamp = timestamp(in: chunk[lineStart..<end]), stamp < since {
                    return probe + UInt64(lineStart - chunk.startIndex)
                }
            }
            step *= 2   // still inside the window, a line too long to see whole, or undated: look further back
        }
        return 0
    }

    /// The `"timestamp":"…"` value of one JSONL line, without parsing the whole line.
    static func timestamp(in line: Data) -> Date? {
        guard let key = line.range(of: Data(#""timestamp":""#.utf8)) else { return nil }
        let value = line[key.upperBound...]
        guard let quote = value.firstIndex(of: UInt8(ascii: "\"")) else { return nil }
        return String(data: value[..<quote], encoding: .utf8).flatMap(OpenUsageISO8601.date(from:))
    }
}
