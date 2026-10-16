import Foundation

enum SSHRemoteUsageError: Error, LocalizedError {
    case invalidConfiguration
    case missingExporter
    case commandFailed(String)
    case oversizedResponse
    case invalidResponse
    case timedOut(TimeInterval)

    var errorDescription: String? {
        switch self {
        case .invalidConfiguration: "Check the SSH host, user, port, and WSL fields. Use plain names without spaces or shell symbols."
        case .missingExporter: "The remote usage exporter is missing from this build."
        case .commandFailed(let detail): "Remote connection failed: \(detail)"
        case .oversizedResponse: "The remote usage response exceeded 32 MB."
        case .invalidResponse: "The remote device returned an unsupported usage format."
        case .timedOut(let seconds):
            "The remote device didn't finish within \(Int(seconds)) seconds. Check that it's awake and its log folders are reachable."
        }
    }
}

/// What one import produces: the priced daily summary that is persisted, and the in-memory live sample.
struct RemoteFetchResult: Sendable {
    let document: UsageHistoryDocument
    let liveSample: RemoteLiveSample
}

struct RemoteUsageEvents: Decodable, Sendable {
    var schema: String
    var codex: [CodexLogUsageScanner.Event]
    var claude: [ClaudeLogUsageScanner.Entry]
}

/// Streams a bundled Python script through SSH stdin. The remote process emits only parsed usage
/// metadata; this Mac uses its canonical pricing and dedup code and persists only a daily summary.
actor SSHRemoteUsageClient {
    static let schema = "openusage.remote-events.v1"
    /// A first import parses a month of logs, so the full fetch gets far longer than the probe.
    static let defaultFetchTimeout: TimeInterval = 180
    static let defaultProbeTimeout: TimeInterval = 30
    static let maxResponseBytes = 32 * 1024 * 1024

    private let executable: String
    private let fetchTimeout: TimeInterval
    private let probeTimeout: TimeInterval

    init(executable: String = "/usr/bin/ssh", fetchTimeout: TimeInterval = SSHRemoteUsageClient.defaultFetchTimeout,
         probeTimeout: TimeInterval = SSHRemoteUsageClient.defaultProbeTimeout) {
        self.executable = executable
        self.fetchTimeout = fetchTimeout
        self.probeTimeout = probeTimeout
    }

    func fetch(_ device: RemoteUsageDevice) async throws -> RemoteFetchResult {
        guard device.isValid else { throw SSHRemoteUsageError.invalidConfiguration }
        guard let url = Bundle.openUsageResources.url(forResource: "remote_usage_export", withExtension: "py")
        else { throw SSHRemoteUsageError.missingExporter }
        let script = try Data(contentsOf: url)
        let output = try await runSSH(device: device, input: script, timeout: fetchTimeout)
        let events: RemoteUsageEvents
        do {
            let decoder = JSONDecoder()
            events = try decoder.decode(RemoteUsageEvents.self, from: output)
        } catch {
            throw SSHRemoteUsageError.invalidResponse
        }
        guard events.schema == Self.schema else { throw SSHRemoteUsageError.invalidResponse }
        let importedAt = Date()
        let liveSample = RemoteLiveSample.from(events: events, deviceID: device.id, importedAt: importedAt)
        let pricing = await ModelPricingStore.shared.current()
        return RemoteFetchResult(
            document: Self.document(device: device, events: events, pricing: pricing, now: importedAt),
            liveSample: liveSample
        )
    }

    /// A cheap check of authentication, the selected runtime, and the remote user's home.
    func probe(_ device: RemoteUsageDevice) async throws -> String {
        guard device.isValid else { throw SSHRemoteUsageError.invalidConfiguration }
        let script = Data("import getpass, pathlib, sys\nprint(sys.platform + ' | ' + getpass.getuser() + ' | ' + str(pathlib.Path.home()))\n".utf8)
        let output = try await runSSH(device: device, input: script, timeout: probeTimeout)
        let response = String(decoding: output, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        let expected = device.platform == .windows ? "win32" : "linux"
        if device.platform == .macOS {
            guard response.hasPrefix("darwin | ") else { throw SSHRemoteUsageError.commandFailed("The remote Python is not running on macOS: \(response)") }
        } else {
            guard response.hasPrefix("\(expected) | ") else { throw SSHRemoteUsageError.commandFailed("The remote Python is running on the wrong system: \(response)") }
        }
        return response
    }

    static func sshArguments(device: RemoteUsageDevice, command: String) -> [String] {
        var arguments = [
            "-T", "-o", "BatchMode=yes", "-o", "StrictHostKeyChecking=yes",
            "-o", "ConnectTimeout=10", "-o", "ServerAliveInterval=10",
            "-o", "ServerAliveCountMax=3"
        ]
        if let user = device.sshUser { arguments += ["-l", user] }
        if let port = device.sshPort { arguments += ["-p", String(port)] }
        arguments += [device.host, command]
        return arguments
    }

    static func document(
        device: RemoteUsageDevice, events: RemoteUsageEvents, pricing: ModelPricing, now: Date = Date()
    ) -> UsageHistoryDocument {
        let since = JSONLScanning.sinceDate(daysBack: 30, now: now)
        var providers: [String: ProviderUsageHistory] = [:]
        if !events.codex.isEmpty {
            let scan = CodexLogUsageScanner.aggregate(events: events.codex, since: since, pricing: pricing)
            providers["codex"] = ProviderUsageHistory(
                series: scan.series, modelUsage: scan.modelUsage,
                unknownModelsByDay: scan.unknownModelsByDay,
                fallbackPricingModelsByDay: scan.fallbackPricingModelsByDay
            )
        }
        if !events.claude.isEmpty {
            let scan = ClaudeLogUsageScanner.aggregate(
                entries: ClaudeLogUsageScanner.dedup(events.claude), since: since, pricing: pricing
            )
            providers["claude"] = ProviderUsageHistory(
                series: scan.series, modelUsage: scan.modelUsage,
                unknownModelsByDay: scan.unknownModelsByDay
            )
        }
        return UsageHistoryDocument(
            deviceID: device.id, deviceName: device.name, updatedAt: now, providers: providers
        )
    }

    /// Runs off the cooperative pool, so the actor stays free for other devices while ssh works.
    private func runSSH(device: RemoteUsageDevice, input: Data, timeout: TimeInterval) async throws -> Data {
        let result: SSHProcess.Output
        do {
            result = try await SSHProcess.run(
                executable: executable, arguments: Self.sshArguments(device: device, command: device.command),
                input: input, timeout: timeout, maxOutput: Self.maxResponseBytes
            )
        } catch SSHProcess.Failure.timedOut {
            throw SSHRemoteUsageError.timedOut(timeout)
        } catch SSHProcess.Failure.oversized {
            throw SSHRemoteUsageError.oversizedResponse
        }
        guard result.status == 0 else {
            throw SSHRemoteUsageError.commandFailed(Self.failureMessage(status: result.status, stderr: result.stderr))
        }
        return result.stdout
    }

    static func failureMessage(status: Int32, stderr: Data) -> String {
        let detail = String(decoding: stderr.prefix(1_024), as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if detail.contains("Permission denied") {
            return "SSH login was rejected. Check the SSH user and key. \(detail)"
        } else if detail.contains("Host key verification failed") {
            return "Trust this host once in Terminal with ssh, then retry. \(detail)"
        } else if detail.contains("not recognized") || detail.contains("not found") {
            return "The selected Python or WSL command is unavailable. \(detail)"
        }
        return detail.isEmpty ? "Remote command exited \(status)." : detail
    }
}
