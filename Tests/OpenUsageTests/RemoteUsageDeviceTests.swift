import XCTest
@testable import OpenUsage

final class RemoteUsageDeviceTests: XCTestCase {
    func testSSHHostValidationRejectsShellSyntax() {
        XCTAssertTrue(RemoteUsageDevice(name: "Lab WSL", host: "lab", platform: .wsl).isValid)
        XCTAssertTrue(RemoteUsageDevice(name: "Linux", host: "compute.example.org", platform: .linux).isValid)
        XCTAssertFalse(RemoteUsageDevice(name: "Lab", host: "lab;touch /tmp/x", platform: .wsl).isValid)
        XCTAssertFalse(RemoteUsageDevice(name: "Lab", host: "-oProxyCommand=evil", platform: .wsl).isValid)
        XCTAssertFalse(RemoteUsageDevice(name: "Lab", host: "lab", platform: .wsl, sshUser: "bad;whoami").isValid)
        XCTAssertTrue(RemoteUsageDevice(name: "Office", host: "windows", platform: .windows, sshUser: "DOMAIN\\person").isValid)
        XCTAssertTrue(RemoteUsageDevice(name: "Office", host: "windows", platform: .windows, sshUser: "person@example.org").isValid)
        XCTAssertFalse(RemoteUsageDevice(name: "Lab", host: "lab", platform: .wsl, sshPort: 0).isValid)
        XCTAssertFalse(RemoteUsageDevice(name: "Lab", host: "lab", platform: .wsl, wslDistribution: "Ubuntu;whoami").isValid)
    }

    func testExplicitWindowsAccountAndWSLUserAreSeparate() {
        let device = RemoteUsageDevice(name: "Lab WSL", host: "100.115.179.72", platform: .wsl,
                                       sshUser: "smilelab", sshPort: 2222,
                                       wslDistribution: "Ubuntu", wslUser: "linuxuser")
        XCTAssertTrue(device.isValid)
        XCTAssertEqual(device.command, "wsl.exe --distribution Ubuntu --user linuxuser --exec python3 -")
        let args = SSHRemoteUsageClient.sshArguments(device: device, command: device.command)
        XCTAssertEqual(Array(args.suffix(6)), ["-l", "smilelab", "-p", "2222", "100.115.179.72", device.command])
        XCTAssertEqual(RemoteUsageDevice(name: "Windows", host: "lab", platform: .windows).command, "py -3 -")
        XCTAssertEqual(RemoteUsageDevice(name: "Mac", host: "mac", platform: .macOS).command, "python3 -")
    }

    func testLegacySavedDeviceDecodesWithoutNewConnectionFields() throws {
        let json = Data(#"{"id":"ssh-lab","name":"Lab","host":"lab","platform":"Windows WSL","enabled":true}"#.utf8)
        let device = try JSONDecoder().decode(RemoteUsageDevice.self, from: json)
        XCTAssertNil(device.sshUser)
        XCTAssertNil(device.sshPort)
        XCTAssertNil(device.wslDistribution)
        XCTAssertNil(device.wslUser)
        XCTAssertEqual(device.command, "wsl.exe --exec python3 -")
    }

    func testRemoteEventsUseCanonicalCodexPricing() throws {
        let now = Date()
        let device = RemoteUsageDevice(name: "Lab WSL", host: "lab", platform: .wsl)
        let rates = ModelRates(inputPerMillion: 1_000_000, outputPerMillion: 2_000_000,
                               cacheWritePerMillion: 1_000_000, cacheReadPerMillion: 100_000)
        let pricing = ModelPricing(supplement: PricingSupplement(),
                                   primary: PricingCatalog(entries: ["gpt-5.2": rates]),
                                   secondary: PricingCatalog(entries: [:]))
        let events = RemoteUsageEvents(
            schema: SSHRemoteUsageClient.schema,
            codex: [CodexLogUsageScanner.Event(
                timestamp: now, model: "gpt-5.2", input: 10, cached: 0,
                output: 2, reasoning: 0, total: 12
            )],
            claude: []
        )

        let document = SSHRemoteUsageClient.document(
            device: device, events: events, pricing: pricing, now: now
        )

        XCTAssertNoThrow(try document.validate())
        XCTAssertEqual(document.deviceID, device.id)
        XCTAssertEqual(document.providers["codex"]?.series.daily.first?.totalTokens, 12)
        XCTAssertEqual(document.providers["codex"]?.series.daily.first?.costUSD, 14)
        XCTAssertNil(document.providers["claude"])
    }

    @MainActor
    func testAllAndPerDeviceScopeDoNotEchoRemoteHistoryIntoLocalExport() throws {
        let suite = "RemoteUsageDeviceTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let day = DailyUsageAccumulator.dayKey(from: .now)
        func history(_ tokens: Int) -> ProviderUsageHistory {
            ProviderUsageHistory(series: DailyUsageSeries(daily: [
                DailyUsageEntry(date: day, totalTokens: tokens, costUSD: Double(tokens))
            ]))
        }
        let provider = Provider(id: "codex", displayName: "Codex", icon: .providerMark("codex"))
        let descriptor = WidgetDescriptor.usageTrend(provider: provider)
            .exportingHistory(scope: .machineLocal, estimatedCost: true, sourceNote: "logs")
        let registry = WidgetRegistry(providers: [provider], descriptors: [descriptor])
        let cache = ProviderSnapshotCache(userDefaults: defaults, storageKey: "snapshots")
        cache.store(ProviderSnapshot(providerID: "codex", displayName: "Codex", lines: [],
                                     usageHistory: history(10)))
        let store = WidgetDataStore(registry: registry, providers: [], cache: cache, defaults: defaults)
        let remote = UsageHistoryDocument(deviceID: "ssh-lab", deviceName: "Lab WSL",
                                          updatedAt: .now, providers: ["codex": history(20)])

        XCTAssertEqual(store.historyScopeID, "all")
        XCTAssertNotNil(registry.historyDescriptorsByProvider["codex"])
        XCTAssertEqual(UsageHistoryAggregator.merged(
            localSnapshots: store.localSnapshots, peerDocuments: [remote],
            descriptors: registry.historyDescriptorsByProvider
        )["codex"]?.series.daily.first?.totalTokens, 30)

        store.setRemoteHistoryDocuments([remote])
        XCTAssertTrue(store.historyScopeOptions.contains { $0.id == "ssh-lab" })
        XCTAssertEqual(store.snapshots["codex"]?.usageHistory?.series.daily.first?.totalTokens, 30)
        store.historyScopeID = "ssh-lab"
        XCTAssertEqual(store.snapshots["codex"]?.usageHistory?.series.daily.first?.totalTokens, 20)
        store.historyScopeID = "local"
        XCTAssertEqual(store.snapshots["codex"]?.usageHistory?.series.daily.first?.totalTokens, 10)
        XCTAssertEqual(store.localHistoryDocument(deviceID: "this-mac", deviceName: "This Mac")
            .providers["codex"]?.series.daily.first?.totalTokens, 10)
    }

    func testHungRemoteFetchFailsWithTimeoutInsteadOfBlocking() async throws {
        // A fake ssh whose remote Python never finishes, e.g. a log folder on a dead network mount.
        let script = FileManager.default.temporaryDirectory.appendingPathComponent("hung-ssh-\(UUID().uuidString)")
        try "#!/bin/sh\nsleep 30\n".write(to: script, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)
        defer { try? FileManager.default.removeItem(at: script) }
        let client = SSHRemoteUsageClient(executable: script.path, fetchTimeout: 1, probeTimeout: 1)
        let device = RemoteUsageDevice(name: "Lab", host: "lab", platform: .linux)
        let started = Date()
        do {
            _ = try await client.fetch(device)
            XCTFail("Expected a timeout")
        } catch SSHRemoteUsageError.timedOut(let seconds) {
            XCTAssertEqual(seconds, 1)
        }
        XCTAssertLessThan(Date().timeIntervalSince(started), 10)
    }

    func testUnattributedRemoteHistoryIsReportedInsteadOfSilentlyDropped() {
        let now = Date()
        let history = ProviderUsageHistory(series: DailyUsageSeries(daily: [
            DailyUsageEntry(date: DailyUsageAccumulator.dayKey(from: now), totalTokens: 50, costUSD: 1)
        ]))
        // Remote summaries never carry account identities.
        let remote = UsageHistoryDocument(deviceID: "ssh-lab", deviceName: "Lab", updatedAt: now,
                                          providers: ["claude": history, "codex": history])
        let descriptor = UsageHistoryDescriptor(scope: .machineLocal, estimatedCost: true, sourceNote: "logs")

        // One Claude login and a plain Codex login: everything is counted, nothing reported.
        let single = ["claude": descriptor, "codex": descriptor]
        XCTAssertEqual(UsageHistoryAggregator.merged(localSnapshots: [:], peerDocuments: [remote],
                                                     descriptors: single, now: now)["claude"]?
            .series.daily.first?.totalTokens, 50)
        XCTAssertTrue(UsageHistoryAggregator.unattributedFamilies(in: remote, descriptors: single).isEmpty)

        // Two Claude cards and two Codex accounts: merged leaves the remote history out, and
        // unattributedFamilies names both so the device row can say so.
        let identities = ["claude@1234abcd": "org-a", "claude@87654321": "org-b",
                          "codex": "a|a@example.com", "codex@1234abcd": "b|b@example.com"]
        let multiple = identities.mapValues { _ in descriptor }
        let merged = UsageHistoryAggregator.merged(localSnapshots: [:], peerDocuments: [remote],
                                                   descriptors: multiple, providerIdentityKeys: identities, now: now)
        XCTAssertTrue(merged.values.allSatisfy { $0.series.daily.isEmpty })
        XCTAssertEqual(UsageHistoryAggregator.unattributedFamilies(
            in: remote, descriptors: multiple, providerIdentityKeys: identities
        ), ["claude", "codex"])

        // A provider turned off on this Mac is the user's choice, not a gap to report.
        XCTAssertTrue(UsageHistoryAggregator.unattributedFamilies(in: remote, descriptors: [:]).isEmpty)
    }
}
