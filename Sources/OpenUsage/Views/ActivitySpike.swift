import SwiftUI

// DESIGN SPIKE (feat/ssh-design-spike): the live-activity look from the Tokamak redesign mockups.
// Speed numbers are a deterministic preview until a real log-watching source exists; today's spend and
// tokens are real. Not production code: kept in one file so the spike is easy to review or drop.

/// Smooth, time-based stand-in for tokens per minute. Every view derives from the same function of
/// time, so the header chips, the headline, and the chart always agree without shared state.
enum LiveActivityPreview {
    static let window: TimeInterval = 30 * 60
    static let samples = 60
    static let families = ["claude", "codex"]

    static func rate(_ family: String, at t: TimeInterval) -> Double {
        switch family {
        case "claude": max(0, 900_000 + 330_000 * sin(t / 173) + 110_000 * sin(t / 37 + 1.3))
        case "codex": max(0, 300_000 + 110_000 * sin(t / 241 + 0.7) + 45_000 * sin(t / 29))
        default: 0
        }
    }

    static func history(_ family: String, endingAt t: TimeInterval) -> [Double] {
        (0..<samples).map { index in
            rate(family, at: t - window + window * Double(index) / Double(samples - 1))
        }
    }

    static func format(_ perMinute: Double) -> String {
        perMinute >= 1_000_000
            ? String(format: "%.2fM", perMinute / 1_000_000)
            : "\(Int((perMinute / 1_000).rounded()))K"
    }
}

enum ActivityPalette {
    static let claude = Color(red: 0.91, green: 0.51, blue: 0.35)
    static let codex = Color(red: 0.25, green: 0.81, blue: 0.66)
    static let device = Color(red: 0.65, green: 0.55, blue: 0.98)
}

/// The top-of-dashboard activity card: headline (speed, today's spend, or today's tokens), a 30-minute
/// stacked chart split by provider or device, and a collapse caret matching the provider cards.
struct ActivityCard: View {
    let todaySpend: Double?
    let todayTokens: Int?
    let remoteDeviceNames: [String]

    enum Headline: String, CaseIterable {
        case speed, spentToday, tokensToday
        var title: String {
            switch self {
            case .speed: "Speed"
            case .spentToday: "Spent Today"
            case .tokensToday: "Tokens Today"
            }
        }
        var unit: String {
            switch self {
            case .speed: "tokens/min"
            case .spentToday: "spent today"
            case .tokensToday: "tokens today"
            }
        }
    }

    enum Breakdown: String, CaseIterable { case providers = "Providers", devices = "Devices" }

    @AppStorage("tokamak.activity.collapsed") private var collapsed = false
    @AppStorage("tokamak.activity.headline") private var headline = Headline.speed
    @AppStorage(DensitySetting.key) private var density = DensitySetting.regular
    @Environment(\.popoverIsVisible) private var shown
    @State private var breakdown = Breakdown.providers

    var body: some View {
        Group {
            if shown {
                TimelineView(.periodic(from: .now, by: 2)) { timeline in
                    card(t: timeline.date.timeIntervalSinceReferenceDate)
                }
            } else {
                card(t: Date().timeIntervalSinceReferenceDate)
            }
        }
        .cardSurface()
    }

    private func card(t: TimeInterval) -> some View {
        let claude = LiveActivityPreview.history("claude", endingAt: t)
        let codex = LiveActivityPreview.history("codex", endingAt: t)
        let total = zip(claude, codex).map(+)
        return VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: 6) {
                LiveDot()
                Text(headlineValue(total.last ?? 0))
                    .font(.system(size: collapsed ? 17 : 24, weight: .semibold))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .lineLimit(1)
                unitMenu
                Spacer(minLength: 6)
                if collapsed {
                    ActivitySparkline(values: total).frame(width: 110, height: 22)
                }
            }
            .frame(minHeight: 30)
            if !collapsed {
                expanded(claude: claude, codex: codex, t: t)
                    .transition(.opacity)
            }
            caret
        }
        .padding(.horizontal, 12)
        .padding(.top, 10)
        .animation(Motion.spring, value: collapsed)
    }

    @ViewBuilder
    private func expanded(claude: [Double], codex: [Double], t: TimeInterval) -> some View {
        let rows = legendRows(t: t)
        VStack(alignment: .leading, spacing: 6) {
            StackedActivityChart(lower: breakdown == .providers ? codex : rows.lowerHistory(claude, codex),
                                 upper: breakdown == .providers ? claude : rows.upperHistory(claude, codex),
                                 lowerColor: breakdown == .providers ? ActivityPalette.codex : ActivityPalette.device,
                                 upperColor: ActivityPalette.claude)
                .frame(height: 44)
                .padding(.top, 8)
            HStack(spacing: 6) {
                Text("Last 30 min")
                    .font(.system(size: density.planBadgePointSize))
                    .foregroundStyle(.secondary)
                Text("Preview")
                    .font(.system(size: density.planBadgePointSize - 1, weight: .medium))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(.quaternary, in: Capsule())
                Spacer(minLength: 4)
                if !remoteDeviceNames.isEmpty {
                    QuietSegmentedControl(selection: $breakdown)
                }
            }
            ForEach(rows.items, id: \.name) { item in
                HStack(spacing: 8) {
                    RoundedRectangle(cornerRadius: 2).fill(item.color).frame(width: 8, height: 8)
                    Text(item.name)
                    if let note = item.note { Text(note).foregroundStyle(.tertiary) }
                    Spacer(minLength: 4)
                    Text(item.rate > 0 ? "\(LiveActivityPreview.format(item.rate))/min" : "—")
                        .monospacedDigit()
                        .foregroundStyle(item.rate > 0 ? .primary : .secondary)
                }
                .font(.system(size: density.supportingPointSize))
            }
        }
    }

    private var unitMenu: some View {
        Menu {
            Picker("Show", selection: $headline) {
                ForEach(Headline.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            .pickerStyle(.inline)
            .labelsHidden()
        } label: {
            // `.button` menu style keeps the label's own order (text, then chevron); `.borderlessButton`
            // moved the chevron in front of the text.
            HStack(spacing: 3) {
                Text(headline.unit)
                if !collapsed {
                    Image(systemName: "chevron.down").font(.system(size: 9, weight: .semibold))
                }
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
        .disabled(collapsed)
        .accessibilityLabel("Headline: \(headline.title)")
    }

    private var caret: some View {
        Button {
            collapsed.toggle()
        } label: {
            Image(systemName: collapsed ? "chevron.down" : "chevron.up")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, minHeight: 24)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(collapsed ? "Show Activity Details" : "Hide Activity Details")
    }

    private func headlineValue(_ speed: Double) -> String {
        switch headline {
        case .speed: return LiveActivityPreview.format(speed)
        case .spentToday: return todaySpend.map { String(format: "$%.2f", $0) } ?? "—"
        case .tokensToday: return todayTokens.map(Self.compactTokens) ?? "—"
        }
    }

    static func compactTokens(_ value: Int) -> String {
        let v = Double(value)
        if v >= 1_000_000_000 { return String(format: "%.1fB", v / 1_000_000_000) }
        if v >= 1_000_000 { return String(format: "%.0fM", v / 1_000_000) }
        if v >= 1_000 { return String(format: "%.0fK", v / 1_000) }
        return "\(value)"
    }

    private struct LegendItem { let name: String; let note: String?; let color: Color; let rate: Double }
    private struct LegendRows {
        let items: [LegendItem]
        let thisMacShare: Double
        func upperHistory(_ claude: [Double], _ codex: [Double]) -> [Double] {
            zip(claude, codex).map { ($0 + $1) * thisMacShare }
        }
        func lowerHistory(_ claude: [Double], _ codex: [Double]) -> [Double] {
            zip(claude, codex).map { ($0 + $1) * (1 - thisMacShare) }
        }
    }

    private func legendRows(t: TimeInterval) -> LegendRows {
        let claude = LiveActivityPreview.rate("claude", at: t)
        let codex = LiveActivityPreview.rate("codex", at: t)
        guard breakdown == .devices, let first = remoteDeviceNames.first else {
            return LegendRows(items: [
                LegendItem(name: "Claude", note: nil, color: ActivityPalette.claude, rate: claude),
                LegendItem(name: "Codex", note: nil, color: ActivityPalette.codex, rate: codex),
            ], thisMacShare: 1)
        }
        let share = 0.68
        var items = [
            LegendItem(name: "This Mac", note: "live", color: ActivityPalette.claude, rate: (claude + codex) * share),
            LegendItem(name: first, note: "updated 2m ago", color: ActivityPalette.device, rate: (claude + codex) * (1 - share)),
        ]
        items += remoteDeviceNames.dropFirst().map {
            LegendItem(name: $0, note: "idle", color: .secondary, rate: 0)
        }
        return LegendRows(items: items, thisMacShare: share)
    }
}

/// A low-key two-option switch (the native segmented control's accent fill was too loud for the card).
struct QuietSegmentedControl: View {
    @Binding var selection: ActivityCard.Breakdown
    @AppStorage(DensitySetting.key) private var density = DensitySetting.regular

    var body: some View {
        HStack(spacing: 2) {
            ForEach(ActivityCard.Breakdown.allCases, id: \.self) { option in
                Button {
                    selection = option
                } label: {
                    Text(option.rawValue)
                        .font(.system(size: density.planBadgePointSize, weight: selection == option ? .medium : .regular))
                        .foregroundStyle(selection == option ? .primary : .secondary)
                        .padding(.horizontal, 8)
                        .frame(minHeight: 22)
                        .background {
                            if selection == option {
                                RoundedRectangle(cornerRadius: 5).fill(Color.primary.opacity(0.12))
                            }
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selection == option ? .isSelected : [])
            }
        }
        .padding(1)
        .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 6))
    }
}

/// A small green dot that breathes slowly while the popover is visible and motion is allowed.
struct LiveDot: View {
    @Environment(\.popoverIsVisible) private var shown
    @Environment(\.reduceAnimations) private var reduceAnimations

    var body: some View {
        let dot = Circle().fill(Color.green).frame(width: 6, height: 6)
        if shown && !reduceAnimations {
            dot.phaseAnimator([false, true]) { view, bright in
                view.opacity(bright ? 1 : 0.45)
            } animation: { _ in .easeInOut(duration: 1.6) }
        } else {
            dot
        }
    }
}

/// "● 982K/min" for a provider header, ticking every 2 s only while the popover is visible.
struct LiveRateLabel: View {
    let family: String
    @AppStorage(DensitySetting.key) private var density = DensitySetting.regular
    @Environment(\.popoverIsVisible) private var shown

    var body: some View {
        Group {
            if shown {
                TimelineView(.periodic(from: .now, by: 2)) { timeline in
                    label(LiveActivityPreview.rate(family, at: timeline.date.timeIntervalSinceReferenceDate))
                }
            } else {
                label(LiveActivityPreview.rate(family, at: Date().timeIntervalSinceReferenceDate))
            }
        }
    }

    private func label(_ rate: Double) -> some View {
        HStack(spacing: 4) {
            LiveDot()
            Text("\(LiveActivityPreview.format(rate))/min").monospacedDigit().contentTransition(.numericText())
        }
        .font(.system(size: density.supportingPointSize, weight: .medium))
        .foregroundStyle(.secondary)
        .accessibilityElement(children: .combine)
    }
}

/// Two stacked areas (lower band, then upper band on top) with the total drawn as a thin line.
struct StackedActivityChart: View {
    let lower: [Double]
    let upper: [Double]
    let lowerColor: Color
    let upperColor: Color

    var body: some View {
        Canvas { context, size in
            let count = min(lower.count, upper.count)
            guard count > 1 else { return }
            let total = (0..<count).map { lower[$0] + upper[$0] }
            let peak = max(total.max() ?? 1, 1) * 1.12
            func point(_ index: Int, _ value: Double) -> CGPoint {
                CGPoint(x: size.width * Double(index) / Double(count - 1), y: size.height * (1 - value / peak))
            }
            var lowerArea = Path()
            lowerArea.move(to: point(0, 0))
            for index in 0..<count { lowerArea.addLine(to: point(index, lower[index])) }
            lowerArea.addLine(to: point(count - 1, 0))
            lowerArea.closeSubpath()
            context.fill(lowerArea, with: .color(lowerColor.opacity(0.38)))

            var upperArea = Path()
            upperArea.move(to: point(0, total[0]))
            for index in 1..<count { upperArea.addLine(to: point(index, total[index])) }
            for index in stride(from: count - 1, through: 0, by: -1) { upperArea.addLine(to: point(index, lower[index])) }
            upperArea.closeSubpath()
            context.fill(upperArea, with: .color(upperColor.opacity(0.38)))

            var line = Path()
            line.move(to: point(0, total[0]))
            for index in 1..<count { line.addLine(to: point(index, total[index])) }
            context.stroke(line, with: .color(.primary.opacity(0.7)), lineWidth: 1.2)
        }
        .accessibilityHidden(true)
    }
}

struct ActivitySparkline: View {
    let values: [Double]

    var body: some View {
        StackedActivityChart(lower: values.map { _ in 0 }, upper: values,
                             lowerColor: .clear, upperColor: ActivityPalette.claude)
    }
}

/// A soft highlight that eases across a live meter's fill, then rests, so the bar feels alive without
/// drawing the eye. Static (invisible) when the popover is hidden or Reduce Animations is on.
struct CalmMeterSweep: View {
    var period: TimeInterval = 12

    var body: some View {
        VisibilityGatedTimeline { t in
            GeometryReader { proxy in
                let phase = t.truncatingRemainder(dividingBy: period) / period
                let progress = min(phase / 0.62, 1)
                let eased = 0.5 - 0.5 * cos(Double.pi * progress)
                let width = max(proxy.size.width * 0.45, 24)
                LinearGradient(colors: [.white.opacity(0), .white.opacity(0.22), .white.opacity(0)],
                               startPoint: .leading, endPoint: .trailing)
                    .frame(width: width)
                    .offset(x: -width + (proxy.size.width + width) * eased)
                    .opacity(progress >= 1 || t == 0 ? 0 : 1)
            }
        }
        .allowsHitTesting(false)
    }
}
