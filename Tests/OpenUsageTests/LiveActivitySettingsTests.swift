import XCTest
@testable import OpenUsage

final class LiveActivitySettingsTests: XCTestCase {
    func testResetAllRestoresLiveDefaults() throws {
        let suite = "LiveActivitySettingsTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(false, forKey: LiveActivitySettings.cardKey)
        defaults.set(false, forKey: LiveActivitySettings.headerSpeedKey)
        defaults.set(false, forKey: LiveActivitySettings.animatedMetersKey)
        defaults.set(true, forKey: LiveActivitySettings.edgeGlowKey)
        defaults.set(false, forKey: LiveActivitySettings.deviceBreakdownKey)
        defaults.set(true, forKey: LiveActivitySettings.collapsedKey)
        defaults.set("tokensToday", forKey: LiveActivitySettings.headlineKey)

        LiveActivitySettings.reset(in: defaults)

        for key in LiveActivitySettings.allKeys {
            XCTAssertNil(defaults.object(forKey: key), "\(key) should fall back to its @AppStorage default")
        }
        XCTAssertEqual(LiveActivitySettings.defaults[LiveActivitySettings.cardKey] as? Bool, true)
        XCTAssertEqual(LiveActivitySettings.defaults[LiveActivitySettings.edgeGlowKey] as? Bool, false)
        XCTAssertEqual(LiveActivitySettings.defaults[LiveActivitySettings.headlineKey] as? String, "speed")
    }
}
