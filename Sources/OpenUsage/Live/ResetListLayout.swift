import Foundation

/// Layout rules for the Rate Limit Resets list: at most two rows until expanded, an orange countdown
/// within three days of expiry, and the largest-unit countdown copy ("in 3d", "in 5h", "in 20m").
enum ResetListLayout {
    static let collapsedLimit = 2
    static let soonThreshold: TimeInterval = 3 * 86_400

    static func visible(total: Int, expanded: Bool) -> (shown: Int, hidden: Int) {
        guard !expanded, total > collapsedLimit else { return (total, 0) }
        return (collapsedLimit, total - collapsedLimit)
    }

    static func isSoon(_ expiry: Date, now: Date) -> Bool {
        expiry.timeIntervalSince(now) <= soonThreshold
    }

    static func countdown(to expiry: Date, now: Date) -> String {
        let seconds = expiry.timeIntervalSince(now)
        guard seconds > 0 else { return "now" }
        if seconds >= 86_400 { return "in \(Int(seconds / 86_400))d" }
        if seconds >= 3_600 { return "in \(Int(seconds / 3_600))h" }
        return "in \(max(1, Int(seconds / 60)))m"
    }
}
