import Foundation

/// Dashboard-only grouping: runs of two or more adjacent Today / Yesterday / Last 30 Days rows render as
/// one three-column Usage row. The metrics themselves (IDs, enablement, pins, order) are unchanged.
enum UsageStatGrouping {
    enum Item: Equatable {
        case single(String)
        case usageStats([String])
    }

    static let statSuffixes = [".today", ".yesterday", ".last30"]

    static func isStat(_ id: String) -> Bool {
        statSuffixes.contains { id.hasSuffix($0) }
    }

    static func group(_ orderedIDs: [String]) -> [Item] {
        var items: [Item] = []
        var run: [String] = []
        func flush() {
            if run.count >= 2 { items.append(.usageStats(run)) } else { items += run.map(Item.single) }
            run = []
        }
        for id in orderedIDs {
            if isStat(id) { run.append(id) } else { flush(); items.append(.single(id)) }
        }
        flush()
        return items
    }
}
