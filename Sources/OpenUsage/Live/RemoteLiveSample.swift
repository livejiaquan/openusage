import Foundation

/// A remote device's recent activity as of its last SSH import. Remote devices are only imported every
/// few minutes, so the rate and chart stay frozen at `importedAt` (never decayed toward "now") and are
/// shown with their age. Memory only: after a relaunch a device has no sample until its next import.
struct RemoteLiveSample: Equatable, Sendable {
    /// Past this age, or after a failed import, the device shows "—" instead of a number.
    static let staleAfter: TimeInterval = 15 * 60

    let deviceID: String
    let importedAt: Date
    let buckets: LiveRateBuckets
    var lastFailureAt: Date?

    var ratePerMinute: Double { buckets.ratePerMinute(now: importedAt) }
    var history: [Double] { buckets.history(now: importedAt) }

    func isAvailable(now: Date) -> Bool {
        guard now.timeIntervalSince(importedAt) <= Self.staleAfter else { return false }
        if let lastFailureAt, lastFailureAt > importedAt { return false }
        return true
    }

    /// Buckets the exporter's events the same way the local tail does: Codex by event total, Claude by
    /// total tokens after the history scanner's dedup.
    static func from(events: RemoteUsageEvents, deviceID: String, importedAt: Date) -> RemoteLiveSample {
        var buckets = LiveRateBuckets(now: importedAt)
        for event in events.codex {
            buckets.add(tokens: event.total, at: event.timestamp, now: importedAt)
        }
        for entry in ClaudeLogUsageScanner.dedup(events.claude) {
            buckets.add(tokens: entry.tokens.totalTokens, at: entry.timestamp, now: importedAt)
        }
        return RemoteLiveSample(deviceID: deviceID, importedAt: importedAt, buckets: buckets)
    }
}
