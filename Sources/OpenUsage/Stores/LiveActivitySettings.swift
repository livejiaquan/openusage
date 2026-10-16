import Foundation

/// `@AppStorage` keys for the Live Activity surfaces (defaults confirmed in the redesign spec).
enum LiveActivitySettings {
    static let cardKey = "tokamak.live.card"                         // default true
    static let headerSpeedKey = "tokamak.live.headerSpeed"           // default true
    static let animatedMetersKey = "tokamak.live.animatedMeters"     // default true
    static let edgeGlowKey = "tokamak.live.edgeGlow"                 // default false
    static let deviceBreakdownKey = "tokamak.live.deviceBreakdown"   // default true
    static let collapsedKey = "tokamak.activity.collapsed"           // default false
    static let headlineKey = "tokamak.activity.headline"             // ActivityHeadline.rawValue, default "speed"

    /// Every key, for Reset All Settings.
    static let allKeys = [cardKey, headerSpeedKey, animatedMetersKey, edgeGlowKey, deviceBreakdownKey,
                          collapsedKey, headlineKey]

    /// The defaults the `@AppStorage` properties declare, kept here so tests and docs agree with them.
    static let defaults: [String: any Sendable] = [
        cardKey: true, headerSpeedKey: true, animatedMetersKey: true, edgeGlowKey: false,
        deviceBreakdownKey: true, collapsedKey: false, headlineKey: ActivityHeadline.speed.rawValue,
    ]

    /// Reset All Settings: removing a key restores its `@AppStorage` default.
    static func reset(in store: UserDefaults = .standard) {
        for key in allKeys { store.removeObject(forKey: key) }
    }
}

enum ActivityHeadline: String, CaseIterable {
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

enum ActivityBreakdown: String, CaseIterable {
    case providers = "Providers"
    case devices = "Devices"
}

/// Compact number formats shared by the Activity card and the header chips.
enum LiveFormat {
    static func rate(_ perMinute: Double) -> String {
        if perMinute >= 1_000_000 { return String(format: "%.2fM", perMinute / 1_000_000) }
        if perMinute >= 1_000 { return "\(Int((perMinute / 1_000).rounded()))K" }
        return "\(Int(perMinute.rounded()))"
    }

    static func tokens(_ value: Int) -> String {
        let v = Double(value)
        if v >= 1_000_000_000 { return String(format: "%.1fB", v / 1_000_000_000) }
        if v >= 1_000_000 { return String(format: "%.0fM", v / 1_000_000) }
        if v >= 1_000 { return String(format: "%.0fK", v / 1_000) }
        return "\(value)"
    }

    static func dollars(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        formatter.locale = Locale(identifier: "en_US")
        return formatter.string(from: NSNumber(value: value)) ?? String(format: "$%.2f", value)
    }
}
