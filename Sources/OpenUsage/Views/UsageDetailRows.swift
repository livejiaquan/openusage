import SwiftUI

/// Today / Yesterday / Last 30 Days as one row of columns (cost in label size, tokens below). Rendered
/// by the dashboard for runs of two or more adjacent spend rows; the metrics themselves are unchanged.
struct UsageStatRow: View {
    let columns: [WidgetData]
    @AppStorage(DensitySetting.key) private var density = DensitySetting.regular
    /// The column whose model breakdown is open (clicking a column with a breakdown opens it).
    @State private var detailIndex: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: density.rowInnerSpacing + 2) {
            Text("Usage").font(.system(size: density.labelPointSize, weight: .semibold))
            HStack(alignment: .top, spacing: 8) {
                ForEach(Array(columns.enumerated()), id: \.offset) { index, data in
                    columnButton(data, index: index).frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, density.barRowPadding)
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
            Text(dollars.map { Formatters.currency($0.number) } ?? (data.hasData ? "—" : "No data"))
                .font(.system(size: density.labelPointSize, weight: .semibold))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            if let tokens {
                Text("\(LiveFormat.tokens(Int(tokens.number))) tokens")
                    .font(.system(size: density.planBadgePointSize))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
    }
}

/// Top Models Today: up to three models by today's cost, each with a thin share bar.
struct TopModelsRow: View {
    let data: WidgetData
    let entries: [TopModelEntry]
    var color: Color = ActivityPalette.claude
    @AppStorage(DensitySetting.key) private var density = DensitySetting.regular

    var body: some View {
        VStack(alignment: .leading, spacing: density.rowInnerSpacing + 2) {
            Text(data.title).font(.system(size: density.labelPointSize, weight: .semibold))
            ForEach(entries, id: \.model) { entry in
                VStack(alignment: .leading, spacing: 3) {
                    HStack {
                        Text(entry.model).lineLimit(1).truncationMode(.middle)
                        Spacer(minLength: 8)
                        Text("\(Int((entry.share * 100).rounded()))% · \(Formatters.currency(entry.cost))")
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                    .font(.system(size: density.supportingPointSize))
                    GeometryReader { proxy in
                        ZStack(alignment: .leading) {
                            Capsule().fill(.quaternary)
                            Capsule().fill(color.opacity(0.8)).frame(width: max(3, proxy.size.width * entry.share))
                        }
                    }
                    .frame(height: 3)
                }
                .accessibilityElement(children: .combine)
            }
        }
    }
}
