import Foundation

struct TopModelEntry: Equatable {
    let model: String
    let cost: Double
    /// Share of the day's cost (or of its tokens when nothing was priced), 0...1.
    let share: Double
}

/// The Top Models Today row: the day's top models from the Today row's existing per-model breakdown,
/// ranked by cost (falling back to tokens when no model was priced). Empty when fewer than two models
/// were used, which hides the row.
enum TopModels {
    static func entries(from breakdown: ModelUsageBreakdown?, limit: Int = 3) -> [TopModelEntry] {
        let models = (breakdown?.models ?? []).filter { $0.totalTokens > 0 || ($0.costUSD ?? 0) > 0 }
        guard models.count >= 2 else { return [] }
        let totalCost = models.compactMap(\.costUSD).reduce(0, +)
        let byCost = totalCost > 0
        let total = byCost ? totalCost : Double(models.map(\.totalTokens).reduce(0, +))
        guard total > 0 else { return [] }
        let ranked = models.map { model in
            TopModelEntry(model: model.model, cost: model.costUSD ?? 0,
                          share: (byCost ? (model.costUSD ?? 0) : Double(model.totalTokens)) / total)
        }
        return Array(ranked.sorted { $0.share > $1.share }.prefix(limit))
    }
}
