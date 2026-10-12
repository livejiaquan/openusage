import XCTest
@testable import OpenUsage

@MainActor
final class CodexHistoryOwnershipRefreshTests: XCTestCase {
    private typealias Fixtures = CodexMultiAccountFixtures

    func testMovedSharedHistoryIsRemovedEvenWhenOldAccountAuthenticationFails() async throws {
        try await assertMovedHistoryIsRemoved(response: HTTPResponse(statusCode: 500, headers: [:], body: Data()))
    }

    func testMovedSharedHistoryIsRemovedWhenOldAccountRefreshSucceedsWithoutOwnedLogs() async throws {
        try await assertMovedHistoryIsRemoved(response: Fixtures.usageResponse())
    }

    func testUnchangedOwnedHistorySurvivesALaterAPIFailure() async throws {
        try await assertMovedHistoryIsRemoved(response: Fixtures.usageResponse(), sharedHistoryMoved: false, laterFailure: true)
    }

    private func assertMovedHistoryIsRemoved(response: HTTPResponse, sharedHistoryMoved: Bool = true,
                                             laterFailure: Bool = false) async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("codex-owner-refresh-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let main = root.appendingPathComponent("main")
        let saved = root.appendingPathComponent("saved-a")
        try FileManager.default.createDirectory(at: main.appendingPathComponent("sessions"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: saved, withIntermediateDirectories: true)
        if sharedHistoryMoved {
            try FileManager.default.createSymbolicLink(atPath: saved.appendingPathComponent("sessions").path,
                                                      withDestinationPath: main.appendingPathComponent("sessions").path)
        } else {
            try FileManager.default.createDirectory(at: saved.appendingPathComponent("sessions"), withIntermediateDirectories: true)
        }
        let now = Date()
        let rollout = CodexLogFixture.tokenCount(timestamp: OpenUsageISO8601.string(from: now),
                                                last: CodexLogFixture.usage(input: 100, output: 50), model: "gpt-5.2")
        try rollout.write(to: (sharedHistoryMoved ? main : saved).appendingPathComponent("sessions/shared.jsonl"),
                          atomically: true, encoding: .utf8)
        let identity = CodexAccountIdentity(accountID: "A", email: "a@test")!
        let files = FakeFiles([
            main.appendingPathComponent("auth.json").path: Fixtures.codexAuth(accountID: "B", email: "b@test"),
            saved.appendingPathComponent("auth.json").path: Fixtures.codexAuth(accountID: "A", email: "a@test")
        ])
        let auth = CodexAuthStore(environment: FakeEnvironment(["CODEX_HOME": main.path]), files: files,
                                  keychain: FakeKeychain(), expectedIdentity: identity, additionalAuthHomes: [saved.path])
        let http = FakeHTTPClient(response: response)
        let provider = CodexProvider.isolated(
            authStore: auth, usageClient: CodexUsageClient(http: http),
            logUsageScanner: CodexLogUsageScanner(incrementalScanner: IncrementalJSONLScanner()),
            historyScope: .account(identity, CodexHistoryHomes(homes: [main.path, saved.path],
                defaultHome: main.path, registeredOwners: [saved.path: identity]), claimsPiUsage: false),
            now: { now }, pricing: { TestPricing.bundled }
        )
        let suite = "CodexHistoryOwnershipRefreshTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let cache = ProviderSnapshotCache(userDefaults: defaults, storageKey: "snapshots")
        let history = ProviderUsageHistory(series: DailyUsageSeries(daily: [
            DailyUsageEntry(date: DailyUsageAccumulator.dayKey(from: now), totalTokens: 150, costUSD: 1)
        ]))
        let cached = ProviderSnapshot(providerID: provider.provider.id, displayName: "Codex", lines: [
            .progress(label: "Weekly", used: 10, limit: 100, format: .percent)
        ], refreshedAt: now, usageHistory: history)
        cache.store(cached, producedByIdentityKey: identity.key)
        let store = WidgetDataStore(
            registry: WidgetRegistry(providers: [provider.provider], descriptors: provider.widgetDescriptors),
            providers: [provider], cache: cache, defaults: defaults,
            providerIdentityKeys: [provider.provider.id: identity.key]
        )
        XCTAssertEqual(store.localSnapshots[provider.provider.id]?.usageHistory?.series.daily.first?.totalTokens, 150)

        _ = await store.refresh(providerID: provider.provider.id, force: true)

        let expected = sharedHistoryMoved ? 0 : 150
        XCTAssertEqual(store.localSnapshots[provider.provider.id]?.usageHistory?.series.daily.reduce(0) { $0 + $1.totalTokens } ?? 0, expected,
                       "History now owned by B must not remain cached on A")
        XCTAssertEqual(cache.loadSnapshots(providerIDs: [provider.provider.id])[provider.provider.id]?.usageHistory?.series.daily.reduce(0) { $0 + $1.totalTokens } ?? 0, expected)
        if laterFailure {
            let successful = try XCTUnwrap(store.localSnapshots[provider.provider.id])
            http.response = HTTPResponse(statusCode: 500, headers: [:], body: Data())
            _ = await store.refresh(providerID: provider.provider.id, force: true)
            XCTAssertEqual(store.localSnapshots[provider.provider.id]?.usageHistory, successful.usageHistory)
            XCTAssertEqual(store.localSnapshots[provider.provider.id]?.refreshedAt, successful.refreshedAt)
        }
        if response.statusCode != 200 {
            XCTAssertEqual(store.localSnapshots[provider.provider.id]?.refreshedAt, cached.refreshedAt)
            XCTAssertEqual(store.localSnapshots[provider.provider.id]?.line(label: "Weekly"), cached.line(label: "Weekly"))
        }
    }
}
