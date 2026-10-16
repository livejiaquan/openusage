import SwiftUI

/// Settings → Live Activity: turns each live surface on or off. With everything off the dashboard looks
/// like OpenUsage's (aside from the glass panel and the restyled On Demand rows).
struct LiveActivitySettingsSection: View {
    @AppStorage(LiveActivitySettings.cardKey) private var card = true
    @AppStorage(LiveActivitySettings.headerSpeedKey) private var headerSpeed = true
    @AppStorage(LiveActivitySettings.animatedMetersKey) private var animatedMeters = true
    @AppStorage(LiveActivitySettings.edgeGlowKey) private var edgeGlow = false
    @AppStorage(LiveActivitySettings.deviceBreakdownKey) private var deviceBreakdown = true
    @AppStorage(DensitySetting.key) private var density = DensitySetting.regular

    var body: some View {
        VStack(alignment: .leading, spacing: density.headerToCardSpacing) {
            Text("Live Activity")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
            VStack(spacing: 0) {
                row("Activity Card", isOn: $card)
                row("Speed on Provider Headers", isOn: $headerSpeed)
                row("Animated Meters", isOn: $animatedMeters)
                row("Edge Glow", isOn: $edgeGlow, indented: true)
                    .disabled(!animatedMeters)
                row("Device Breakdown", isOn: $deviceBreakdown)
                Text("Live speed is read from this Mac's Claude and Codex logs while the panel is open. Remote devices update at each import.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 8)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .cardSurface()
        }
    }

    private func row(_ title: String, isOn: Binding<Bool>, indented: Bool = false) -> some View {
        HStack(spacing: 10) {
            Text(title)
            Spacer(minLength: 8)
            Toggle("", isOn: isOn).settingsSwitchStyle()
        }
        .padding(.leading, indented ? 28 : 12)
        .padding(.trailing, 12)
        .padding(.vertical, density.controlRowPadding)
    }
}
