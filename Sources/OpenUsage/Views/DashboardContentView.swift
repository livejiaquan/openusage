import SwiftUI

/// The dashboard-only scrolling content. Screen switching, panel sizing, fixed bars, keyboard handling,
/// and close/reset behavior stay with `DashboardView`.
struct DashboardContentView: View {
    let container: AppContainer
    let layout: LayoutStore
    let updater: UpdaterController
    let reorderSpaceName: String
    let horizontalPadding: CGFloat
    let bottomGap: CGFloat

    @Binding var reorderLift: ReorderLift?
    @Binding var scrollPosition: ScrollPosition

    @AppStorage(DensitySetting.key) private var density = DensitySetting.regular
    @AppStorage(TotalSpendSetting.key) private var showTotalSpend = true

    var body: some View {
        PopoverScrollView {
            VStack(alignment: .leading, spacing: 0) {
                // A pending update found by a scheduled Sparkle check tops everything — it's the
                // reminder the buried Sparkle window can't deliver for a dockless app.
                if let updateVersion = updater.availableUpdateVersion {
                    UpdateBannerCard(version: updateVersion)
                        .padding(.bottom, density.sectionSpacing)
                        .transition(.scale(scale: 0.95).combined(with: .opacity))
                }
                // The one-time first-run hint sits above the provider sections (and above the
                // empty-state line, which a fresh install can hit while nothing has data yet).
                if container.onboarding.isCustomizeHintPending {
                    CustomizeHintCard()
                        .padding(.bottom, density.sectionSpacing)
                        .transition(.scale(scale: 0.95).combined(with: .opacity))
                }
                widgetContent
            }
            .animation(Motion.spring, value: container.onboarding.isCustomizeHintPending)
            .animation(Motion.spring, value: updater.availableUpdateVersion)
            .padding(.horizontal, horizontalPadding)
            .padding(.top, density.contentTopPadding)
            .padding(.bottom, bottomGap)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollPosition($scrollPosition)
    }

    @ViewBuilder
    private var widgetContent: some View {
        if container.dataStore.historyScopeOptions.count > 2 {
            HStack(spacing: 8) {
                Text("Usage From")
                    .foregroundStyle(.secondary)
                Spacer(minLength: 4)
                Menu {
                    ForEach(container.dataStore.historyScopeOptions.map { $0.id }, id: \.self) { id in
                        Button {
                            container.dataStore.historyScopeID = id
                        } label: {
                            if container.dataStore.historyScopeID == id {
                                Label(scopeName(id), systemImage: "checkmark")
                            } else {
                                Text(scopeName(id))
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text(scopeName(container.dataStore.historyScopeID))
                        Image(systemName: "chevron.down")
                    }
                    .foregroundStyle(.primary)
                }
                .menuIndicator(.hidden)
            }
            .font(.caption)
            .padding(.bottom, density.sectionSpacing)
        }
        // DESIGN SPIKE: live activity card above the totals.
        ActivityCard(
            todaySpend: todayTotals.spend,
            todayTokens: todayTotals.tokens,
            remoteDeviceNames: container.remoteDevices.devices.map(\.name)
        )
        .padding(.bottom, density.sectionSpacing)
        // The cross-provider Total Spend ring stays visible whenever the user allows it and an enabled
        // provider can track spend, even before fresh data arrives or when every metric row is hidden.
        if showTotalSpend, layout.hasSpendCapableProvider {
            TotalSpendCard()
                .padding(.bottom, density.sectionSpacing)
        }
        if layout.displayGroups.isEmpty {
            Text("Turn on Customize to choose what to show.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 24)
                .padding(.horizontal, 16)
        } else {
            WidgetGroupedListView(
                reorderSpaceName: reorderSpaceName,
                reorderLift: $reorderLift
            )
        }
    }

    /// Today's spend and tokens across the providers shown, from the same daily history the rows use.
    private var todayTotals: (spend: Double?, tokens: Int?) {
        let key = DailyUsageAccumulator.dayKey(from: Date())
        var spend = 0.0, tokens = 0, sawCost = false, sawDay = false
        for snapshot in container.dataStore.snapshots.values {
            guard let day = snapshot.usageHistory?.series.daily.first(where: { $0.date == key }) else { continue }
            sawDay = true
            tokens += day.totalTokens
            if let cost = day.costUSD { spend += cost; sawCost = true }
        }
        return (sawCost ? spend : nil, sawDay ? tokens : nil)
    }

    private func scopeName(_ id: String) -> String {
        container.dataStore.historyScopeOptions.first(where: { $0.id == id })?.name ?? "All Devices"
    }
}
