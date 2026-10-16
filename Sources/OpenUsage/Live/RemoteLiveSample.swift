import Foundation

/// A remote device's recent activity as of its last SSH import. Remote devices are only imported every
/// few minutes, so the rate and chart stay frozen at `importedAt` (never decayed toward "now") and are
/// shown with their age. Memory only: after a relaunch a device has no sample until its next import.
struct RemoteLiveSample: Equatable, Sendable {
    /// Past this age, or after a failed import, the device shows "—" instead of a number.
    static let staleAfter: TimeInterval = 15 * 60

    let deviceID: String
    let importedAt: Date
    /// Kept per provider so a single-device scope can still fill the Claude and Codex header chips.
    let familyBuckets: [LiveFamily: LiveRateBuckets]
    var lastFailureAt: Date?

    var buckets: LiveRateBuckets { LiveRateBuckets.merged(Array(familyBuckets.values), now: importedAt) }
    var ratePerMinute: Double { buckets.ratePerMinute(now: importedAt) }
    var history: [Double] { buckets.history(now: importedAt) }

    func ratePerMinute(_ family: LiveFamily) -> Double {
        familyBuckets[family]?.ratePerMinute(now: importedAt) ?? 0
    }

    func history(_ family: LiveFamily) -> [Double] {
        (familyBuckets[family] ?? LiveRateBuckets(now: importedAt)).history(now: importedAt)
    }

    /// Chart points (trailing-five-minute rate), frozen at `importedAt` like the rate.
    var smoothedHistory: [Double] { buckets.smoothedHistory(now: importedAt) }

    func smoothedHistory(_ family: LiveFamily) -> [Double] {
        (familyBuckets[family] ?? LiveRateBuckets(now: importedAt)).smoothedHistory(now: importedAt)
    }

    /// The same sample with only these providers' activity.
    func restricted(to families: Set<LiveFamily>) -> RemoteLiveSample {
        RemoteLiveSample(deviceID: deviceID, importedAt: importedAt,
                         familyBuckets: familyBuckets.filter { families.contains($0.key) },
                         lastFailureAt: lastFailureAt)
    }

    func isAvailable(now: Date) -> Bool {
        guard now.timeIntervalSince(importedAt) <= Self.staleAfter else { return false }
        if let lastFailureAt, lastFailureAt > importedAt { return false }
        return true
    }

    /// Buckets the exporter's events the same way the local tail does: Codex by event total, Claude by
    /// total tokens after the history scanner's dedup.
    static func from(events: RemoteUsageEvents, deviceID: String, importedAt: Date) -> RemoteLiveSample {
        var codex = LiveRateBuckets(now: importedAt)
        for event in events.codex {
            codex.add(tokens: event.total, at: event.timestamp, now: importedAt)
        }
        var claude = LiveRateBuckets(now: importedAt)
        for entry in ClaudeLogUsageScanner.dedup(events.claude) {
            claude.add(tokens: entry.tokens.totalTokens, at: entry.timestamp, now: importedAt)
        }
        return RemoteLiveSample(deviceID: deviceID, importedAt: importedAt,
                                familyBuckets: [.claude: claude, .codex: codex])
    }
}
