import Foundation
import Observation

/// Live token speed for the dashboard. Works only while the panel is visible: `setVisible(true)` starts
/// a 2-second poll of the local log tails plus an FSEvents watcher that polls immediately on writes;
/// `setVisible(false)` cancels both, so a closed panel costs nothing.
@MainActor
@Observable
final class LiveActivityStore {
    static let pollInterval: Duration = .seconds(2)

    @ObservationIgnored private let tails: [LiveFamily: LiveLogTail]
    @ObservationIgnored private let watchedRoots: [URL]
    @ObservationIgnored private let remoteDevices: RemoteUsageDeviceStore
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private var pollTask: Task<Void, Never>?
    @ObservationIgnored private var watcher: LogDirectoryWatcher?
    @ObservationIgnored private var polling = false

    private(set) var local: [LiveFamily: LiveRateBuckets] = [:]

    init(tails: [LiveFamily: LiveLogTail], watchedRoots: [URL], remoteDevices: RemoteUsageDeviceStore,
         now: @escaping () -> Date = Date.init) {
        self.tails = tails
        self.watchedRoots = watchedRoots
        self.remoteDevices = remoteDevices
        self.now = now
    }

    func setVisible(_ visible: Bool) {
        if visible {
            guard pollTask == nil else { return }
            pollTask = Task { [weak self] in
                while !Task.isCancelled {
                    await self?.pollOnce()
                    try? await Task.sleep(for: Self.pollInterval)
                }
            }
            let watcher = LogDirectoryWatcher(paths: watchedRoots) { [weak self] in
                Task { @MainActor in await self?.pollOnce() }
            }
            watcher.start()
            self.watcher = watcher
        } else {
            pollTask?.cancel()
            pollTask = nil
            watcher?.stop()
            watcher = nil
        }
    }

    func view(scope: String, enabledFamilies: Set<LiveFamily>) -> LiveActivityView {
        LiveActivityComposer.compose(scope: scope, local: local, remote: Array(remoteDevices.liveSamples.values),
                                     devices: remoteDevices.devices, now: now(), enabledFamilies: enabledFamilies)
    }

    private func pollOnce() async {
        guard !polling else { return }
        polling = true
        defer { polling = false }
        var next: [LiveFamily: LiveRateBuckets] = [:]
        for (family, tail) in tails {
            next[family] = await tail.poll(now: now())
        }
        if next != local { local = next }
    }

    /// The default Claude and Codex homes (plus `CLAUDE_CONFIG_DIR` / `CODEX_HOME` overrides) that the
    /// watcher listens to; missing folders are skipped by the watcher.
    static func defaultWatchedRoots(environment: [String: String] = ProcessInfo.processInfo.environment,
                                    home: URL = FileManager.default.homeDirectoryForCurrentUser) -> [URL] {
        func split(_ key: String) -> [URL] {
            (environment[key] ?? "").split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
                .map { URL(fileURLWithPath: expandHome($0)) }
        }
        return [home.appendingPathComponent(".claude"), home.appendingPathComponent(".config/claude"),
                home.appendingPathComponent(".codex")] + split("CLAUDE_CONFIG_DIR") + split("CODEX_HOME")
    }
}
