import SwiftUI

/// A soft highlight that eases across a live meter's fill, then rests, so the bar feels alive without
/// drawing the eye. Faster burn shortens the cycle (8–16 s). Invisible when the panel is hidden or
/// Reduce Animations is on (`VisibilityGatedTimeline` renders t == 0 then).
struct CalmMeterSweep: View {
    /// Tokens per minute that map to the fastest cycle.
    static let peakRate: Double = 1_500_000

    static func period(forRate rate: Double) -> TimeInterval? {
        guard rate > 0 else { return nil }
        return 16 - 8 * min(rate / peakRate, 1)
    }

    let period: TimeInterval
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VisibilityGatedTimeline { t in
            GeometryReader { proxy in
                let phase = t.truncatingRemainder(dividingBy: period) / period
                let progress = min(phase / 0.62, 1)          // travel, then rest for the remaining 38%
                let eased = 0.5 - 0.5 * cos(Double.pi * progress)
                let width = max(proxy.size.width * 0.45, 24)
                let peak = colorScheme == .dark ? 0.16 : 0.5
                LinearGradient(colors: [.white.opacity(0), .white.opacity(peak), .white.opacity(0)],
                               startPoint: .leading, endPoint: .trailing)
                    .frame(width: width)
                    .offset(x: -width + (proxy.size.width + width) * eased)
                    .opacity(progress >= 1 || t == 0 ? 0 : 1)
            }
        }
        .allowsHitTesting(false)
    }
}

/// The optional faint glow at a live meter's leading edge (4.5 s breathing, opacity 0.15–0.45).
struct MeterEdgeGlow: View {
    var body: some View {
        VisibilityGatedTimeline { t in
            let opacity = t == 0 ? 0 : 0.3 + 0.15 * sin(t * 2 * Double.pi / 4.5)
            Circle()
                .fill(RadialGradient(colors: [Color(red: 0.55, green: 0.78, blue: 1).opacity(0.9), .clear],
                                     center: .center, startRadius: 0, endRadius: 7))
                .frame(width: 14, height: 14)
                .opacity(opacity)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// "● 982K/min" on a provider header.
struct LiveRateChip: View {
    let providerName: String
    let rate: Double
    @AppStorage(DensitySetting.key) private var density = DensitySetting.regular

    var body: some View {
        HStack(spacing: 4) {
            LiveDot(active: rate > 0)
            Text("\(LiveFormat.rate(rate))/min").monospacedDigit().contentTransition(.numericText())
        }
        .font(.system(size: density.supportingPointSize, weight: .medium))
        .foregroundStyle(.secondary)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(providerName), \(Int(rate.rounded())) tokens per minute")
    }
}
