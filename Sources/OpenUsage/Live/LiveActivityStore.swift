import Foundation
import Observation

/// Live token speed for the dashboard. While the panel is visible, `setVisible(true)` runs a 2-second poll
/// of the local log tails plus an FSEvents watcher that polls immediately on writes. While it is closed, a
/// 30-second background poll keeps the tails caught up (reading only appended bytes), so opening the
/// panel never has to swallow a long backlog and the speed is current on the first frame.
@MainActor
@Observable
final class LiveActivityStore {
    static let pollInterval: Duration = .seconds(2)
    static let backgroundInterval: Duration = .seconds(30)

    @ObservationIgnored private let tails: [LiveFamily: LiveLogTail]
    @ObservationIgnored private let watchedRoots: [URL]
    @ObservationIgnored private let remoteDevices: RemoteUsageDeviceStore
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private var pollTask: Task<Void, Never>?
    @ObservationIgnored private var backgroundTask: Task<Void, Never>?
    @ObservationIgnored private var watcher: LogDirectoryWatcher?
    @ObservationIgnored private var polling = false

    private(set) var local: [LiveFamily: LiveRateBuckets] = [:]
    /// False until the first poll finishes, so the card can say "Measuring…" instead of a blank.
    private(set) var hasMeasured = false

    init(tails: [LiveFamily: LiveLogTail], watchedRoots: [URL], remoteDevices: RemoteUsageDeviceStore,
         now: @escaping () -> Date = Date.init) {
        self.tails = tails
        self.watchedRoots = watchedRoots
        self.remoteDevices = remoteDevices
        self.now = now
    }

    func setVisible(_ visible: Bool) {
        if visible {
            backgroundTask?.cancel()
            backgroundTask = nil
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
            startBackgroundPolling()
        }
    }

    private func startBackgroundPolling() {
        guard backgroundTask == nil else { return }
        backgroundTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: Self.backgroundInterval)
                guard !Task.isCancelled else { return }
                await self?.pollOnce()
            }
        }
    }

    /// One poll at launch, so the first time the panel opens it already has a speed (later opens keep
    /// the buckets from the previous session and catch up on the bytes written while closed).
    func prewarm() {
        Task { [weak self] in
            await self?.pollOnce()
            guard let self, self.pollTask == nil else { return }
            self.startBackgroundPolling()
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
        let started = Date()
        var next: [LiveFamily: LiveRateBuckets] = [:]
        for (family, tail) in tails {
            next[family] = await tail.poll(now: now())
        }
        let changed = next != local
        if changed { local = next }
        let elapsed = Date().timeIntervalSince(started)
        // Lines up with `PanelPerfMonitor` stalls when tracing a hitch to the live poll.
        if elapsed >= 0.05 {
            AppLog.info(.statusItem, "perf: live poll took \(Int(elapsed * 1000)) ms (changed: \(changed))")
        }
        if !hasMeasured { hasMeasured = true }
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
