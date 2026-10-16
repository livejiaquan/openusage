import Foundation

/// Whether the cross-provider Total Spend card shows at the top of the dashboard. Off by default in
/// Tokamak (the Activity card's headline already offers today's spend); the toggle sits at the top of
/// Settings → General. Hiding it only affects the card — the
/// per-provider spend rows it aggregates stay wherever the user put them.
enum TotalSpendSetting {
    static let key = "showTotalSpend"
    static let defaultShown = false
    /// The card's selected period (Today / Yesterday / 30 Days), persisted by `TotalSpendCard`.
    static let periodKey = "openusage.totalSpend.period"
    /// The card's selected metric (Cost / Cost/MTok / Tokens), persisted by `TotalSpendCard`.
    static let metricKey = "openusage.totalSpend.metric"
}
