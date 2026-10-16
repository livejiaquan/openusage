import Foundation

struct LiveSeries: Equatable, Identifiable {
    let id: String
    let name: String
    let note: String?
    /// 60 points in tokens per minute, oldest first; nil when the source has nothing current to show.
    let history: [Double]?
    let rate: Double?
}

/// Everything the live surfaces (Activity card, header chips) show for one Usage From scope.
struct LiveActivityView: Equatable {
    var totalRate: Double?
    var providerRates: [LiveFamily: Double]
    var providerSeries: [LiveSeries]
    var deviceSeries: [LiveSeries]
    var showsDeviceBreakdown: Bool
}

/// Pure composition of local and remote live data for a scope, so the rules (scope filtering, frozen
/// remote rates, stale devices shown as "—") are testable without a SwiftUI host.
enum LiveActivityComposer {
    static let thisMacID = "local"

    static func compose(
        scope: String, local: [LiveFamily: LiveRateBuckets], remote: [RemoteLiveSample],
        devices: [RemoteUsageDevice], now: Date, enabledFamilies: Set<LiveFamily> = Set(LiveFamily.allCases)
    ) -> LiveActivityView {
        let knownIDs = Set(devices.map(\.id))
        let scope = (scope == "all" || scope == thisMacID || knownIDs.contains(scope)) ? scope : "all"
        // A provider turned off in Customize leaves every live surface, like it leaves Total Spend.
        let local = local.filter { enabledFamilies.contains($0.key) }
        let samples = Dictionary(remote.map { ($0.deviceID, $0.restricted(to: enabledFamilies)) },
                                 uniquingKeysWith: { $1 })
        let available = samples.filter { $0.value.isAvailable(now: now) }

        let includesLocal = scope == "all" || scope == thisMacID
        let remoteInScope: [RemoteLiveSample] = switch scope {
        case "all": devices.compactMap { available[$0.id] }
        case thisMacID: []
        default: available[scope].map { [$0] } ?? []
        }

        var providerRates: [LiveFamily: Double] = [:]
        var providerSeries: [LiveSeries] = []
        for family in LiveFamily.allCases where enabledFamilies.contains(family) {
            let localBuckets = includesLocal ? local[family] : nil
            let parts = (localBuckets.map { [$0.history(now: now)] } ?? []) + remoteInScope.map { $0.history(family) }
            guard !parts.isEmpty else { continue }
            let rate = (localBuckets?.ratePerMinute(now: now) ?? 0) + remoteInScope.map { $0.ratePerMinute(family) }.reduce(0, +)
            providerRates[family] = rate
            providerSeries.append(LiveSeries(id: family.rawValue, name: family == .claude ? "Claude" : "Codex",
                                             note: nil, history: sum(parts), rate: rate))
        }

        var deviceSeries: [LiveSeries] = []
        if includesLocal, !local.isEmpty {
            let merged = LiveRateBuckets.merged(Array(local.values), now: now)
            deviceSeries.append(LiveSeries(id: thisMacID, name: "This Mac", note: "live",
                                           history: merged.history(now: now), rate: merged.ratePerMinute(now: now)))
        }
        for device in devices where scope == "all" || scope == device.id {
            if let sample = available[device.id] {
                deviceSeries.append(LiveSeries(id: device.id, name: device.name,
                                               note: "updated \(age(now.timeIntervalSince(sample.importedAt)))",
                                               history: sample.history, rate: sample.ratePerMinute))
            } else {
                let note = samples[device.id].map { "last import \(age(now.timeIntervalSince($0.importedAt)))" }
                    ?? "not imported yet"
                deviceSeries.append(LiveSeries(id: device.id, name: device.name, note: note, history: nil, rate: nil))
            }
        }

        let totalRate: Double? = providerSeries.isEmpty ? nil : providerRates.values.reduce(0, +)
        return LiveActivityView(totalRate: totalRate, providerRates: providerRates, providerSeries: providerSeries,
                                deviceSeries: deviceSeries, showsDeviceBreakdown: scope == "all" && !devices.isEmpty)
    }

    /// The single provider card per family that shows the live chip: the bare family id ("claude"), or,
    /// when only account cards exist, the card whose account occupies the default home (`ownerIDs`) —
    /// the live tail reads the default home's logs, so reordering cards never moves the chip.
    static func chipFamily(forProviderID id: String, providerIDs: [String],
                           ownerIDs: [LiveFamily: String] = [:]) -> LiveFamily? {
        guard let family = LiveFamily(rawValue: ProviderAccountID.family(of: id)) else { return nil }
        if providerIDs.contains(family.rawValue) { return id == family.rawValue ? family : nil }
        guard let owner = ownerIDs[family], providerIDs.contains(owner) else { return nil }
        return id == owner ? family : nil
    }

    /// Card id per family whose account currently occupies the default home, from the account registry.
    static func defaultSourceOwners(_ records: [ProviderAccountRecord]) -> [LiveFamily: String] {
        var owners: [LiveFamily: String] = [:]
        for record in records where !record.removedTombstone {
            guard let family = LiveFamily(rawValue: record.family), owners[family] == nil,
                  record.sources.contains(where: { $0.kind == .defaultHome && $0.holdsDefaultSource })
            else { continue }
            owners[family] = record.id
        }
        return owners
    }

    private static func sum(_ parts: [[Double]]) -> [Double] {
        guard let first = parts.first else { return [] }
        return parts.dropFirst().reduce(first) { total, next in zip(total, next).map(+) }
    }

    private static func age(_ seconds: TimeInterval) -> String {
        seconds < 60 ? "just now" : "\(Int(seconds / 60))m ago"
    }
}
