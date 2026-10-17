import SwiftUI

/// Today / Yesterday / Last 30 Days as one row of columns (cost in label size, tokens below). Rendered
/// by the dashboard for runs of two or more adjacent spend rows; the metrics themselves are unchanged.
struct UsageStatRow: View {
    let columns: [WidgetData]
    var showsTopDivider = false
    @AppStorage(DensitySetting.key) private var density = DensitySetting.regular
    /// The column whose model breakdown is open (clicking a column with a breakdown opens it).
    @State private var detailIndex: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            OnDemandGroupHeader(title: "Usage")
            HStack(alignment: .top, spacing: 8) {
                ForEach(Array(columns.enumerated()), id: \.offset) { index, data in
                    columnButton(data, index: index).frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, OnDemandGroupRhythm.top(density, divided: showsTopDivider))
        .padding(.bottom, OnDemandGroupRhythm.bottom(density))
        .overlay(alignment: .top) {
            if showsTopDivider { OnDemandGroupDivider() }
        }
        .accessibilityElement(children: .contain)
    }

    /// Each column keeps what the single spend row offered: the incomplete-pricing warning and, when the
    /// period has one, its model breakdown.
    @ViewBuilder
    private func columnButton(_ data: WidgetData, index: Int) -> some View {
        if let breakdown = data.modelBreakdown {
            Button { detailIndex = index } label: {
                column(data).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint("Shows the model breakdown")
            .popover(isPresented: Binding(get: { detailIndex == index },
                                          set: { if !$0 { detailIndex = nil } }),
                     arrowEdge: .trailing) {
                ModelUsageDetail(title: data.title, breakdown: breakdown) { _ in }
            }
        } else {
            column(data)
        }
    }

    private func column(_ data: WidgetData) -> some View {
        let dollars = data.values.first { $0.kind == .dollars }
        let tokens = data.values.first { $0.kind == .count }
        return VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: 3) {
                Text(data.title == "Last 30 Days" ? "30 Days" : data.title)
                    .font(.system(size: density.planBadgePointSize))
                    .foregroundStyle(.secondary)
                if data.hasUnknownModels {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: density.planBadgePointSize - 1))
                        .foregroundStyle(Theme.meterFill(.warning))
                        .hoverTooltip(data.unknownModelTooltip)
                        .accessibilityLabel("This period used a model with unknown pricing")
                }
            }
            // The period's cost is the card's headline figure, a step above the 13 pt text.
            Text(dollars.map { Formatters.currency($0.number) } ?? (data.hasData ? "—" : "No data"))
                .font(.system(size: density.labelPointSize + 2, weight: .semibold))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            if let tokens {
                Text("\(LiveFormat.tokens(Int(tokens.number))) tokens")
                    .font(.system(size: density.planBadgePointSize))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
    }
}

/// Top Models Today as one composition bar: each model's share of today's cost is a segment (the
/// provider color, lighter for each next model; whatever the top three leave is track), with an aligned
/// legend underneath — swatch, name, share, cost — so every figure sits on the same right edge.
struct TopModelsRow: View {
    let data: WidgetData
    let entries: [TopModelEntry]
    var color: Color = ActivityPalette.claude
    @AppStorage(DensitySetting.key) private var density = DensitySetting.regular

    static let shadeOpacities: [Double] = [1, 0.7, 0.35]

    private func shade(_ index: Int) -> Color {
        color.opacity(Self.shadeOpacities[min(index, Self.shadeOpacities.count - 1)])
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            OnDemandGroupHeader(title: data.title)
            compositionBar
                .frame(height: 8)
                // Title baseline to bar matches the other groups' baseline to first line (≈13.5 pt).
                .padding(.top, 2.5)
                .padding(.bottom, 8)
            VStack(spacing: 4) {
                ForEach(Array(entries.enumerated()), id: \.element.model) { index, entry in
                    legendRow(entry, index: index)
                }
            }
        }
        .accessibilityElement(children: .contain)
    }

    /// Segments laid out at exact offsets (2 pt apart) over the track, so shares that add up to 100% fill
    /// it edge to edge with no sliver of track left at the end.
    private var compositionBar: some View {
        GeometryReader { proxy in
            let gap: CGFloat = 2
            let usable = max(0, proxy.size.width - gap * CGFloat(max(entries.count - 1, 0)))
            let widths = entries.map { max(2, usable * $0.share) }
            ZStack(alignment: .leading) {
                Color.primary.opacity(0.1)
                ForEach(Array(entries.enumerated()), id: \.element.model) { index, _ in
                    Rectangle()
                        .fill(shade(index))
                        .frame(width: widths[index])
                        .offset(x: widths[..<index].reduce(0, +) + gap * CGFloat(index))
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
        }
        .accessibilityHidden(true)
    }

    private func legendRow(_ entry: TopModelEntry, index: Int) -> some View {
        HStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 2, style: .continuous).fill(shade(index)).frame(width: 8, height: 8)
            Text(entry.model).lineLimit(1).truncationMode(.middle)
            Spacer(minLength: 4)
            Text("\(Int((entry.share * 100).rounded()))%")
                .foregroundStyle(.secondary)
                .frame(width: 36, alignment: .trailing)
            Text(Formatters.currency(entry.cost))
                .frame(width: 66, alignment: .trailing)
        }
        .font(.system(size: density.supportingPointSize + 1))
        .monospacedDigit()
        .accessibilityElement(children: .combine)
    }
}

/// One vertical rhythm for On Demand groups, so the hairline between two groups sits exactly halfway:
/// every group ends `bottom` below its last line, and a divided group starts the same distance under
/// the line. The first group under the caret (no line) sits closer, since the caret already separates it.
enum OnDemandGroupRhythm {
    /// Under a line, 2 pt less than the gap above it: a title's text box carries ~3 pt of space over its
    /// capitals that the line above a group's last row doesn't, so equal boxes read lopsided (measured
    /// 11 pt above vs 13.5 pt below); this optical correction makes the ink gaps match.
    static func top(_ density: DensitySetting, divided: Bool) -> CGFloat {
        divided ? density.barRowPadding - 2 : density.textRowPadding
    }

    static func bottom(_ density: DensitySetting) -> CGFloat { density.barRowPadding }
}

/// The hairline between On Demand groups, inset to the card's content edges.
struct OnDemandGroupDivider: View {
    var body: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.08))
            .frame(height: 0.5)
            .padding(.horizontal, 12)
            .accessibilityHidden(true)
    }
}

/// The quiet title over an On Demand group (Rate Limit Resets, Top Models Today, Usage): 12 pt secondary,
/// a step below the figures, so the eye lands on the numbers first. An optional trailing note sits right.
struct OnDemandGroupHeader: View {
    let title: String
    var trailing: String? = nil
    @AppStorage(DensitySetting.key) private var density = DensitySetting.regular

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).fontWeight(.medium)
            Spacer(minLength: 8)
            if let trailing { Text(trailing).monospacedDigit() }
        }
        .font(.system(size: density.supportingPointSize))
        .foregroundStyle(.secondary)
        .padding(.bottom, 7)
        .accessibilityAddTraits(.isHeader)
    }
}
