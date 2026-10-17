import SwiftUI

// Leaf views that read the live store themselves. Each 2-second live update re-renders only these, not
// the dashboard and every provider card around them (reading the store in the list's body made every
// update re-render the whole panel, which showed up as 100–300 ms stalls).

extension AppContainer {
    /// Live tokens per minute for one provider family in the current Usage From scope.
    func liveRate(_ family: LiveFamily) -> Double? {
        liveActivity.view(scope: dataStore.historyScopeID, enabledFamilies: liveEnabledFamilies).providerRates[family]
    }
}

/// The Activity card with its live inputs.
struct ActivityCardSlot: View {
    let container: AppContainer

    var body: some View {
        let totals = todayTotals
        ActivityCard(
            live: container.liveActivity.view(scope: container.dataStore.historyScopeID,
                                              enabledFamilies: container.liveEnabledFamilies),
            measuring: !container.liveActivity.hasMeasured,
            todaySpend: totals.spend,
            todayTokens: totals.tokens,
            alert: container.dataStore.runOutAlert()
        )
    }

    /// Today's spend and tokens for the current Usage From scope (the rendered snapshots already are),
    /// over enabled providers only — a disabled provider keeps its last snapshot but leaves the totals.
    private var todayTotals: (spend: Double?, tokens: Int?) {
        let key = DailyUsageAccumulator.dayKey(from: Date())
        var spend = 0.0, tokens = 0, sawCost = false, sawDay = false
        for (providerID, snapshot) in container.dataStore.snapshots where container.enablement.isEnabled(providerID) {
            guard let day = snapshot.usageHistory?.series.daily.first(where: { $0.date == key }) else { continue }
            sawDay = true
            tokens += day.totalTokens
            if let cost = day.costUSD { spend += cost; sawCost = true }
        }
        return (sawCost ? spend : nil, sawDay ? tokens : nil)
    }
}

/// "● 982K/min" on the provider header that owns its family's live chip.
struct LiveRateChipSlot: View {
    let family: LiveFamily
    let providerName: String
    @Environment(AppContainer.self) private var container: AppContainer?

    var body: some View {
        if let rate = container?.liveRate(family) {
            LiveRateChip(providerName: providerName, rate: rate)
        }
    }
}

/// The calm sweep over a live Session meter, paced by the family's current speed.
struct LiveSweepSlot: View {
    let family: LiveFamily
    @Environment(AppContainer.self) private var container: AppContainer?

    var body: some View {
        if let period = container?.liveRate(family).flatMap(CalmMeterSweep.period(forRate:)) {
            CalmMeterSweep(period: period)
        }
    }
}

/// The optional edge glow, shown only while the family is using tokens.
struct LiveEdgeGlowSlot: View {
    let family: LiveFamily
    @Environment(AppContainer.self) private var container: AppContainer?

    var body: some View {
        if let rate = container?.liveRate(family), rate > 0 {
            MeterEdgeGlow()
        }
    }
}
