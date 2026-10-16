import SwiftUI

/// The top-of-dashboard live card: a headline (speed, today's spend, or today's tokens), a 30-minute
/// stacked chart by provider or device, an optional run-out alert, and a caret that works like the
/// provider cards': it sits right under the headline and the details open *below* it, so expanding and
/// collapsing happen at the same spot. Collapsed, it is one line with a sparkline.
struct ActivityCard: View {
    let live: LiveActivityView
    /// The first speed reading hasn't arrived yet (a cold launch scanning the logs).
    var measuring = false
    let todaySpend: Double?
    let todayTokens: Int?
    /// Shown only when some enabled limit is projected to run out before its reset.
    var alert: RunOutAlert?

    @AppStorage(LiveActivitySettings.collapsedKey) private var collapsed = false
    @AppStorage(LiveActivitySettings.headlineKey) private var headline = ActivityHeadline.speed
    @AppStorage(LiveActivitySettings.deviceBreakdownKey) private var deviceBreakdownEnabled = true
    @AppStorage(DensitySetting.key) private var density = DensitySetting.regular
    @State private var breakdown = ActivityBreakdown.providers

    private var showsBreakdownSwitch: Bool { deviceBreakdownEnabled && live.showsDeviceBreakdown }
    private var activeBreakdown: ActivityBreakdown { showsBreakdownSwitch ? breakdown : .providers }
    private var series: [LiveSeries] { activeBreakdown == .providers ? live.providerSeries : live.deviceSeries }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            headlineRow
            caret
            if !collapsed {
                details
                    .padding(.bottom, 12)
                    .transition(.opacity)
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 10)
        .cardSurface()
        .animation(Motion.spring, value: collapsed)
    }

    private var headlineRow: some View {
        HStack(alignment: .center, spacing: 6) {
            LiveDot(active: (live.totalRate ?? 0) > 0)
            Text(headlineValue)
                .font(.system(size: collapsed ? (density == .compact ? 15 : 17) : (density == .compact ? 20 : 24),
                              weight: .semibold))
                .foregroundStyle(speedState == .live || headline != .speed ? .primary : .secondary)
                .monospacedDigit()
                .contentTransition(.numericText())
                .lineLimit(1)
                .fixedSize()
                .layoutPriority(2)
            unitMenu.layoutPriority(1)
            Spacer(minLength: 6)
            if collapsed {
                if alert != nil {
                    // The run-out warning lives in the details; collapsed, a small mark says there is one.
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: density.supportingPointSize - 1))
                        .foregroundStyle(Theme.notice)
                        .accessibilityLabel("Run-out warning, expand to read")
                }
                StackedActivityChart(layers: layers)
                    .frame(minWidth: 40, maxWidth: 110)
                    .frame(height: 22)
            }
        }
        .frame(minHeight: 30)
        .accessibilityElement(children: .contain)
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 6) {
            StackedActivityChart(layers: layers)
                .frame(height: 44)
            HStack(spacing: 6) {
                Text("Last 30 min")
                    .font(.system(size: density.planBadgePointSize))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 4)
                if showsBreakdownSwitch {
                    QuietSegmentedControl(selection: $breakdown)
                }
            }
            ForEach(Array(series.enumerated()), id: \.element.id) { index, item in
                legendRow(item, color: ActivityPalette.color(for: item, index: index, breakdown: activeBreakdown))
            }
            if let alert {
                alertLine(alert)
            }
        }
    }

    private func legendRow(_ item: LiveSeries, color: Color) -> some View {
        HStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 2).fill(color).frame(width: 8, height: 8)
            Text(item.name)
            if let note = item.note { Text(note).foregroundStyle(.tertiary).lineLimit(1) }
            Spacer(minLength: 4)
            Text(item.rate.map { "\(LiveFormat.rate($0))/min" } ?? "—")
                .monospacedDigit()
                .foregroundStyle(item.rate == nil ? .secondary : .primary)
        }
        .font(.system(size: density.supportingPointSize))
        .accessibilityElement(children: .combine)
    }

    private func alertLine(_ alert: RunOutAlert) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill")
            Text("\(Text(alert.providerName).fontWeight(.semibold)) \(alert.message)")
                .fixedSize(horizontal: false, vertical: true)
        }
        .font(.system(size: density.supportingPointSize))
        .foregroundStyle(Theme.notice)
        .padding(.horizontal, 9)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.13), in: RoundedRectangle(cornerRadius: 9))
        .overlay { RoundedRectangle(cornerRadius: 9).strokeBorder(Color.orange.opacity(0.35), lineWidth: 0.5) }
        .padding(.top, 4)
        .accessibilityElement(children: .combine)
    }

    private var unitMenu: some View {
        Menu {
            Picker("Show", selection: $headline) {
                ForEach(ActivityHeadline.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            .pickerStyle(.inline)
            .labelsHidden()
        } label: {
            // `.button` keeps the label's own order: the text, then the chevron.
            HStack(spacing: 3) {
                Text(unitText).lineLimit(1)
                MenuChevron()
            }
            .font(.system(size: density.supportingPointSize))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 6)
            .frame(minHeight: 24)
            .contentShape(Rectangle())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .accessibilityLabel("Headline: \(headline.title)")
    }

    private var caret: some View {
        Button {
            collapsed.toggle()
        } label: {
            DisclosureChevron(expanded: !collapsed)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, minHeight: 24)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(collapsed ? "Show Activity Details" : "Hide Activity Details")
    }

    private var layers: [(values: [Double], color: Color)] {
        series.enumerated().compactMap { index, item in
            item.history.map { ($0, ActivityPalette.color(for: item, index: index, breakdown: activeBreakdown)) }
        }
    }

    private enum SpeedState { case measuring, idle, live }

    /// Speed has three honest states: still reading the logs, nothing in use, or a live number.
    private var speedState: SpeedState {
        if let rate = live.totalRate, rate > 0 { return .live }
        return measuring ? .measuring : .idle
    }

    /// The unit beside the number, or — while speed is idle — when things last moved.
    private var unitText: String {
        guard headline == .speed else { return headline.unit }
        switch speedState {
        case .live: return headline.unit
        case .measuring: return "reading logs"
        case .idle:
            guard let last = live.lastActiveAt else { return "no activity in 30 min" }
            let seconds = Date().timeIntervalSince(last)
            return seconds < 60 ? "last active just now" : "last active \(Formatters.compactDuration(seconds) ?? "1m") ago"
        }
    }

    private var headlineValue: String {
        switch headline {
        case .speed:
            switch speedState {
            case .live: return live.totalRate.map(LiveFormat.rate) ?? "—"
            case .measuring: return "Measuring…"
            case .idle: return "Idle"
            }
        case .spentToday: return (Self.debugSpend ?? todaySpend).map(LiveFormat.dollars) ?? "—"
        case .tokensToday: return todayTokens.map(LiveFormat.tokens) ?? "—"
        }
    }

    /// Launch with `-TokamakDebugHeadline 12345.67` to check long values for truncation.
    private static let debugSpend: Double? = UserDefaults.standard.string(forKey: "TokamakDebugHeadline").flatMap(Double.init)
}
