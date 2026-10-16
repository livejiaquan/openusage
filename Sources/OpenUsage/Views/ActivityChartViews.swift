import SwiftUI

enum ActivityPalette {
    static let claude = Color(red: 0.91, green: 0.51, blue: 0.35)
    static let codex = Color(red: 0.25, green: 0.81, blue: 0.66)
    static let devices = [Color(red: 0.65, green: 0.55, blue: 0.98), Color(red: 0.36, green: 0.66, blue: 0.98),
                          Color(red: 0.95, green: 0.7, blue: 0.3)]

    static func color(for series: LiveSeries, index: Int, breakdown: ActivityBreakdown) -> Color {
        guard series.rate != nil else { return .secondary }
        switch breakdown {
        case .providers: return series.id == LiveFamily.codex.rawValue ? codex : claude
        case .devices:
            if series.id == LiveActivityComposer.thisMacID { return claude }
            return devices[(index - 1 + devices.count) % devices.count]
        }
    }
}

/// Stacked areas, bottom series first, with the running total drawn as a thin line on top.
struct StackedActivityChart: View {
    let layers: [(values: [Double], color: Color)]

    var body: some View {
        Canvas { context, size in
            let layers = layers.filter { $0.values.count > 1 }
            guard let count = layers.map(\.values.count).min(), count > 1 else { return }
            var baseline = Array(repeating: 0.0, count: count)
            let totals = (0..<count).map { index in layers.reduce(0) { $0 + $1.values[index] } }
            let peak = max(totals.max() ?? 0, 1) * 1.12
            func point(_ index: Int, _ value: Double) -> CGPoint {
                CGPoint(x: size.width * Double(index) / Double(count - 1), y: size.height * (1 - value / peak))
            }
            for layer in layers {
                let top = (0..<count).map { baseline[$0] + layer.values[$0] }
                var area = Path()
                area.move(to: point(0, top[0]))
                Self.addCurve(&area, through: (0..<count).map { point($0, top[$0]) })
                let lower = (0..<count).reversed().map { point($0, baseline[$0]) }
                area.addLine(to: lower[0])
                Self.addCurve(&area, through: lower)
                area.closeSubpath()
                context.fill(area, with: .color(layer.color.opacity(0.38)))
                baseline = top
            }
            var line = Path()
            line.move(to: point(0, totals[0]))
            Self.addCurve(&line, through: (0..<count).map { point($0, totals[$0]) })
            context.stroke(line, with: .color(.primary.opacity(0.7)),
                           style: StrokeStyle(lineWidth: 1.2, lineCap: .round, lineJoin: .round))
        }
        .accessibilityHidden(true)
    }

    /// A smooth curve through `points` (Catmull-Rom as cubic Béziers), starting from the path's current
    /// point, which must be `points[0]`. Control points are clamped vertically to their segment so the
    /// curve never overshoots below zero or above a peak.
    static func addCurve(_ path: inout Path, through points: [CGPoint]) {
        guard points.count > 1 else { return }
        for index in 0..<(points.count - 1) {
            let p0 = points[max(index - 1, 0)], p1 = points[index]
            let p2 = points[index + 1], p3 = points[min(index + 2, points.count - 1)]
            let low = min(p1.y, p2.y), high = max(p1.y, p2.y)
            let c1 = CGPoint(x: p1.x + (p2.x - p0.x) / 6, y: min(max(p1.y + (p2.y - p0.y) / 6, low), high))
            let c2 = CGPoint(x: p2.x - (p3.x - p1.x) / 6, y: min(max(p2.y - (p3.y - p1.y) / 6, low), high))
            path.addCurve(to: p2, control1: c1, control2: c2)
        }
    }
}

/// A low-key two-option switch; the native segmented control's accent fill is too loud in the card.
struct QuietSegmentedControl: View {
    @Binding var selection: ActivityBreakdown
    @AppStorage(DensitySetting.key) private var density = DensitySetting.regular

    var body: some View {
        HStack(spacing: 2) {
            ForEach(ActivityBreakdown.allCases, id: \.self) { option in
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
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Breakdown")
    }
}

/// A small green dot that breathes slowly (4.5 s) while the panel is visible and motion is allowed.
/// Opacity is a pure function of the clock (`VisibilityGatedTimeline`): one stable view whatever the
/// state, so the dot never restarts its animation or picks up a neighbor's layout animation when the
/// number beside it changes, the card collapses, or the panel reopens.
struct LiveDot: View {
    var active = true

    var body: some View {
        VisibilityGatedTimeline { t in
            Circle()
                .fill(active ? Color.green : Color.secondary)
                .opacity(active && t != 0 ? 0.725 + 0.275 * cos(t * 2 * Double.pi / 4.5) : 1)
        }
        .frame(width: 6, height: 6)
        .accessibilityHidden(true)
    }
}
