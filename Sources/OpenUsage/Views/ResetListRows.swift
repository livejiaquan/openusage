import SwiftUI

/// Rate Limit Resets as list rows on the dashboard: one row per reset sorted by expiry, at most two
/// until "Show N More". **Use** appears only when the provider has a claim service (Codex) and opens the
/// existing resets popover, which owns the confirm and claim flow.
struct ResetListRows: View {
    let data: WidgetData
    let claim: ((_ expiry: Date, _ redeemRequestID: String) async -> ResetClaimOutcome)?

    @AppStorage(DensitySetting.key) private var density = DensitySetting.regular
    @State private var expanded = false
    @State private var claimTarget: Date?

    private var expiries: [Date] { data.expiriesAt.sorted() }

    var body: some View {
        VStack(alignment: .leading, spacing: density.rowInnerSpacing + 2) {
            HStack(alignment: .firstTextBaseline) {
                Text(data.title).font(.system(size: density.labelPointSize, weight: .semibold))
                Spacer(minLength: 8)
                Text("\(data.resetCreditCount) available")
                    .font(.system(size: density.supportingPointSize))
                    .foregroundStyle(.secondary)
            }
            if expiries.isEmpty {
                Text(data.resetCreditCount == 0 ? "No resets available" : "Expiry times unavailable")
                    .font(.system(size: density.supportingPointSize))
                    .foregroundStyle(.secondary)
            } else {
                TimelineView(.periodic(from: .now, by: 60)) { context in
                    rows(now: context.date)
                }
            }
        }
    }

    private func rows(now: Date) -> some View {
        let layout = ResetListLayout.visible(total: expiries.count, expanded: expanded)
        return VStack(alignment: .leading, spacing: 4) {
            ForEach(Array(expiries.prefix(layout.shown).enumerated()), id: \.offset) { index, expiry in
                row(number: index + 1, expiry: expiry, now: now)
            }
            if expiries.count > ResetListLayout.collapsedLimit {
                Button {
                    withAnimation(Motion.spring) { expanded.toggle() }
                } label: {
                    HStack(spacing: 5) {
                        Text(expanded ? "Show Less" : "Show \(layout.hidden) More")
                        DisclosureChevron(expanded: expanded, size: 9)
                    }
                    .font(.system(size: density.supportingPointSize))
                    .foregroundStyle(.secondary)
                    .padding(.leading, 26)
                    .frame(maxWidth: .infinity, minHeight: 24, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func row(number: Int, expiry: Date, now: Date) -> some View {
        HStack(spacing: 8) {
            Text("\(number)")
                .font(.system(size: 10.5, weight: .semibold))
                .frame(width: 18, height: 18)
                .background(Circle().fill(Color.primary.opacity(0.1)))
            Text("Expires \(Formatters.monthDayLabel(expiry))")
            Spacer(minLength: 4)
            Text(ResetListLayout.countdown(to: expiry, now: now))
                .monospacedDigit()
                .foregroundStyle(ResetListLayout.isSoon(expiry, now: now) ? Theme.notice : AnyShapeStyle(.secondary))
            if claim != nil {
                Button("Use") { claimTarget = expiry }
                    .buttonStyle(.plain)
                    .font(.system(size: density.planBadgePointSize, weight: .medium))
                    .padding(.horizontal, 10)
                    .frame(minHeight: 24)
                    .background(Capsule().fill(Color.primary.opacity(0.09)))
                    .contentShape(Capsule())
                    .accessibilityLabel("Use reset \(number), expires \(Formatters.monthDayLabel(expiry))")
                    .popover(isPresented: Binding(get: { claimTarget == expiry },
                                                  set: { if !$0 { claimTarget = nil } }),
                             arrowEdge: .trailing) {
                        RateLimitResetsDetail(count: data.resetCreditCount, expiries: expiries,
                                              onHoverChange: { _ in }, onPinChange: nil, claim: claim,
                                              startConfirmingAt: expiry)
                            .padding(10)
                    }
            }
        }
        .font(.system(size: density.supportingPointSize))
        .accessibilityElement(children: .contain)
    }
}
