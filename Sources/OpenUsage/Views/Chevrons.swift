import SwiftUI

/// The disclosure arrow for every expand/collapse control. One glyph that rotates (instead of swapping
/// `chevron.up`/`chevron.down`), so collapsing and expanding read as one smooth motion.
struct DisclosureChevron: View {
    let expanded: Bool
    var size: CGFloat = 10

    var body: some View {
        Image(systemName: "chevron.down")
            .font(.system(size: size, weight: .semibold))
            .rotationEffect(.degrees(expanded ? 180 : 0))
            .accessibilityHidden(true)
    }
}

/// The small arrow after a pull-down menu's label ("All Devices", "tokens/min", "Options").
struct MenuChevron: View {
    var body: some View {
        Image(systemName: "chevron.down")
            .font(.system(size: 9, weight: .semibold))
            .accessibilityHidden(true)
    }
}
