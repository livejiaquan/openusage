import XCTest
@testable import OpenUsage

final class RemoteLiveSampleTests: XCTestCase {
    private let importedAt = Date(timeIntervalSinceReferenceDate: 800_000_000)

    private func events(codexAt offsets: [TimeInterval], tokens: Int = 1_000) -> RemoteUsageEvents {
        RemoteUsageEvents(
            schema: SSHRemoteUsageClient.schema,
            codex: offsets.map {
                CodexLogUsageScanner.Event(timestamp: importedAt.addingTimeInterval($0), model: "gpt-5.2",
                                           input: tokens, cached: 0, output: 0, reasoning: 0, total: tokens)
            },
            claude: []
        )
    }

    func testSampleBucketsRecentEvents() {
        let sample = RemoteLiveSample.from(events: events(codexAt: [-120, -40 * 60]), deviceID: "ssh-lab", importedAt: importedAt)
        XCTAssertEqual(sample.ratePerMinute, 100, accuracy: 0.001)    // only the -2 min event, /10 min
        XCTAssertEqual(sample.history.reduce(0, +), 2_000, accuracy: 0.001)
    }

    func testClaudeDuplicatesCountOnce() {
        let entry = ClaudeLogUsageScanner.Entry(timestamp: importedAt.addingTimeInterval(-60),
                                                tokens: TokenBreakdown(input: 500),
                                                messageID: "m1", requestID: "r1")
        let events = RemoteUsageEvents(schema: SSHRemoteUsageClient.schema, codex: [], claude: [entry, entry])
        let sample = RemoteLiveSample.from(events: events, deviceID: "ssh-lab", importedAt: importedAt)
        XCTAssertEqual(sample.ratePerMinute, 50, accuracy: 0.001)
        XCTAssertEqual(sample.ratePerMinute(.claude), 50, accuracy: 0.001)
        XCTAssertEqual(sample.ratePerMinute(.codex), 0, accuracy: 0.001)
    }

    func testSampleGoesStaleAfterFifteenMinutes() {
        let sample = RemoteLiveSample.from(events: events(codexAt: [-60]), deviceID: "ssh-lab", importedAt: importedAt)
        XCTAssertTrue(sample.isAvailable(now: importedAt.addingTimeInterval(14 * 60)))
        XCTAssertFalse(sample.isAvailable(now: importedAt.addingTimeInterval(16 * 60)))
    }

    func testFailureAfterImportMakesSampleUnavailable() {
        var sample = RemoteLiveSample.from(events: events(codexAt: [-60]), deviceID: "ssh-lab", importedAt: importedAt)
        sample.lastFailureAt = importedAt.addingTimeInterval(-300)
        XCTAssertTrue(sample.isAvailable(now: importedAt.addingTimeInterval(60)), "an older failure doesn't matter")
        sample.lastFailureAt = importedAt.addingTimeInterval(120)
        XCTAssertFalse(sample.isAvailable(now: importedAt.addingTimeInterval(180)))
    }

    @MainActor
    func testSamplesAreNotPersisted() throws {
        let suite = "RemoteLiveSampleTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let provider = Provider(id: "codex", displayName: "Codex", icon: .providerMark("codex"))
        let registry = WidgetRegistry(providers: [provider], descriptors: [])
        let cache = ProviderSnapshotCache(userDefaults: defaults, storageKey: "snapshots")
        let dataStore = WidgetDataStore(registry: registry, providers: [], cache: cache, defaults: defaults)
        let store = RemoteUsageDeviceStore(dataStore: dataStore, defaults: defaults)
        XCTAssertTrue(store.liveSamples.isEmpty)
    }
}
