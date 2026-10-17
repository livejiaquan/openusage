import SwiftUI

/// A soft highlight that eases across a live meter's fill, then rests, so the bar feels alive without
/// drawing the eye. Faster burn shortens the cycle (8–16 s). Invisible when the panel is hidden or
/// Reduce Animations is on.
struct CalmMeterSweep: View {
    /// Tokens per minute that map to the fastest cycle.
    nonisolated static let peakRate: Double = 1_500_000

    nonisolated static func period(forRate rate: Double) -> TimeInterval? {
        guard rate > 0 else { return nil }
        return 16 - 8 * min(rate / peakRate, 1)
    }

    let period: TimeInterval
    @Environment(\.popoverIsVisible) private var shown
    @Environment(\.reduceAnimations) private var reduceAnimations

    var body: some View {
        // Drawn by Core Animation (`MeterSweepLayer`), so the panel isn't re-rendered every frame.
        MeterSweepLayer(period: period, animate: shown && !reduceAnimations)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

/// The optional faint glow at a live meter's leading edge (4.5 s breathing, opacity 0.15–0.45).
struct MeterEdgeGlow: View {
    @Environment(\.popoverIsVisible) private var shown
    @Environment(\.reduceAnimations) private var reduceAnimations

    var body: some View {
        EdgeGlowLayer(animate: shown && !reduceAnimations)
            .frame(width: 14, height: 14)
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
            Text(rate > 0 ? "\(LiveFormat.rate(rate))/min" : "idle")
                .monospacedDigit()
                .contentTransition(.numericText())
        }
        .font(.system(size: density.supportingPointSize, weight: .medium))
        .foregroundStyle(.secondary)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(rate > 0 ? "\(providerName), \(Int(rate.rounded())) tokens per minute" : "\(providerName), idle")
    }
}
