import XCTest
@testable import OpenUsage

final class LiveActivityComposerTests: XCTestCase {
    private let now = Date(timeIntervalSinceReferenceDate: 800_000_000)
    private let lab = RemoteUsageDevice(id: "ssh-lab", name: "Lab WSL", host: "lab", platform: .wsl)
    private let office = RemoteUsageDevice(id: "ssh-office", name: "Office", host: "office", platform: .linux)

    private func buckets(_ tokens: Int, at offset: TimeInterval = -60, anchor: Date? = nil) -> LiveRateBuckets {
        let anchor = anchor ?? now
        var buckets = LiveRateBuckets(now: anchor)
        buckets.add(tokens: tokens, at: anchor.addingTimeInterval(offset), now: anchor)
        return buckets
    }

    private func sample(_ device: RemoteUsageDevice, claude: Int, importedAgo: TimeInterval = 120) -> RemoteLiveSample {
        let importedAt = now.addingTimeInterval(-importedAgo)
        return RemoteLiveSample(deviceID: device.id, importedAt: importedAt,
                                familyBuckets: [.claude: buckets(claude, anchor: importedAt)])
    }

    private var local: [LiveFamily: LiveRateBuckets] { [.claude: buckets(1_000), .codex: buckets(500)] }

    func testAllScopeSumsLocalAndAvailableRemote() {
        let view = LiveActivityComposer.compose(scope: "all", local: local, remote: [sample(lab, claude: 2_000)],
                                                devices: [lab], now: now)
        XCTAssertEqual(view.totalRate ?? -1, (1_000 + 500 + 2_000) / 5, accuracy: 0.001)
        XCTAssertEqual(view.providerRates[.claude] ?? -1, 600, accuracy: 0.001)
        XCTAssertEqual(view.providerRates[.codex] ?? -1, 100, accuracy: 0.001)
        XCTAssertEqual(view.deviceSeries.map(\.name), ["This Mac", "Lab WSL"])
        XCTAssertTrue(view.showsDeviceBreakdown)
    }

    func testThisMacScopeIgnoresRemote() {
        let view = LiveActivityComposer.compose(scope: "local", local: local, remote: [sample(lab, claude: 2_000)],
                                                devices: [lab], now: now)
        XCTAssertEqual(view.totalRate ?? -1, 300, accuracy: 0.001)
        XCTAssertEqual(view.deviceSeries.map(\.name), ["This Mac"])
        XCTAssertFalse(view.showsDeviceBreakdown)
    }

    func testSingleDeviceScopeUsesOnlyThatDevice() {
        let view = LiveActivityComposer.compose(scope: "ssh-lab", local: local, remote: [sample(lab, claude: 2_000)],
                                                devices: [lab, office], now: now)
        XCTAssertEqual(view.totalRate ?? -1, 400, accuracy: 0.001)
        XCTAssertEqual(view.providerRates[.claude] ?? -1, 400, accuracy: 0.001)
        XCTAssertEqual(view.providerRates[.codex] ?? -1, 0, accuracy: 0.001)
        XCTAssertEqual(view.deviceSeries.map(\.name), ["Lab WSL"])
        XCTAssertEqual(view.deviceSeries.first?.note, "updated 2m ago")
        XCTAssertFalse(view.showsDeviceBreakdown)
    }

    func testUnavailableRemoteShowsDashNotZero() {
        let stale = sample(lab, claude: 2_000, importedAgo: 20 * 60)
        let view = LiveActivityComposer.compose(scope: "all", local: local, remote: [stale], devices: [lab], now: now)
        let row = view.deviceSeries.first { $0.id == "ssh-lab" }
        XCTAssertNil(row?.rate)
        XCTAssertNil(row?.history)
        XCTAssertEqual(row?.note, "last import 20m ago")
        XCTAssertEqual(view.totalRate ?? -1, 300, accuracy: 0.001, "a stale device adds nothing")
    }

    func testDeviceWithoutImportSaysSo() {
        let view = LiveActivityComposer.compose(scope: "all", local: local, remote: [], devices: [lab], now: now)
        XCTAssertEqual(view.deviceSeries.last?.note, "not imported yet")
        XCTAssertNil(view.deviceSeries.last?.rate)
    }

    func testUnknownScopeFallsBackToAll() {
        let all = LiveActivityComposer.compose(scope: "all", local: local, remote: [], devices: [lab], now: now)
        let removed = LiveActivityComposer.compose(scope: "ssh-gone", local: local, remote: [], devices: [lab], now: now)
        XCTAssertEqual(removed, all)
    }

    func testNothingInScopeHasNoTotal() {
        let view = LiveActivityComposer.compose(scope: "local", local: [:], remote: [], devices: [], now: now)
        XCTAssertNil(view.totalRate)
    }

    func testChipFamilyPrefersBareID() {
        let ids = ["claude@aaaa1111", "claude", "codex"]
        XCTAssertEqual(LiveActivityComposer.chipFamily(forProviderID: "claude", providerIDs: ids), .claude)
        XCTAssertNil(LiveActivityComposer.chipFamily(forProviderID: "claude@aaaa1111", providerIDs: ids))
        XCTAssertEqual(LiveActivityComposer.chipFamily(forProviderID: "codex", providerIDs: ids), .codex)
        XCTAssertNil(LiveActivityComposer.chipFamily(forProviderID: "cursor", providerIDs: ids + ["cursor"]))
    }

    func testChipFamilyFallsBackToFirstAccountCard() {
        let ids = ["codex@11112222", "codex@33334444"]
        XCTAssertEqual(LiveActivityComposer.chipFamily(forProviderID: "codex@11112222", providerIDs: ids), .codex)
        XCTAssertNil(LiveActivityComposer.chipFamily(forProviderID: "codex@33334444", providerIDs: ids))
    }
}
