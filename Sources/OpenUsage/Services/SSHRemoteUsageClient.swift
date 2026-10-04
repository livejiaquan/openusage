import Foundation

enum SSHRemoteUsageError: Error, LocalizedError {
    case invalidConfiguration
    case missingExporter
    case commandFailed(String)
    case oversizedResponse
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .invalidConfiguration: "Check the SSH host, user, port, and WSL fields. Use plain names without spaces or shell symbols."
        case .missingExporter: "The remote usage exporter is missing from this build."
        case .commandFailed(let detail): "Remote connection failed: \(detail)"
        case .oversizedResponse: "The remote usage response exceeded 32 MB."
        case .invalidResponse: "The remote device returned an unsupported usage format."
        }
    }
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

    func fetch(_ device: RemoteUsageDevice) async throws -> UsageHistoryDocument {
        guard device.isValid else { throw SSHRemoteUsageError.invalidConfiguration }
        guard let url = Bundle.openUsageResources.url(forResource: "remote_usage_export", withExtension: "py")
        else { throw SSHRemoteUsageError.missingExporter }
        let script = try Data(contentsOf: url)
        let output = try runSSH(device: device, command: device.command, input: script)
        let events: RemoteUsageEvents
        do {
            let decoder = JSONDecoder()
            events = try decoder.decode(RemoteUsageEvents.self, from: output)
        } catch {
            throw SSHRemoteUsageError.invalidResponse
        }
        guard events.schema == Self.schema else { throw SSHRemoteUsageError.invalidResponse }
        let pricing = await ModelPricingStore.shared.current()
        return Self.document(device: device, events: events, pricing: pricing)
    }

    /// A cheap check of authentication, the selected runtime, and the remote user's home.
    func probe(_ device: RemoteUsageDevice) throws -> String {
        guard device.isValid else { throw SSHRemoteUsageError.invalidConfiguration }
        let script = Data("import getpass, pathlib, sys\nprint(sys.platform + ' | ' + getpass.getuser() + ' | ' + str(pathlib.Path.home()))\n".utf8)
        let output = try runSSH(device: device, command: device.command, input: script)
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

    private func runSSH(device: RemoteUsageDevice, command: String, input: Data) throws -> Data {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ssh")
        process.arguments = Self.sshArguments(device: device, command: command)
        let stdin = Pipe()
        let stdout = Pipe()
        let stderr = Pipe()
        process.standardInput = stdin
        process.standardOutput = stdout
        process.standardError = stderr
        try process.run()
        do { try stdin.fileHandleForWriting.write(contentsOf: input) }
        catch { process.terminate() }
        try? stdin.fileHandleForWriting.close()
        var output = Data()
        while let chunk = try stdout.fileHandleForReading.read(upToCount: 65_536), !chunk.isEmpty {
            output.append(chunk)
            if output.count > 32 * 1024 * 1024 {
                process.terminate()
                throw SSHRemoteUsageError.oversizedResponse
            }
        }
        let errors = stderr.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let detail = String(decoding: errors.prefix(1_024), as: UTF8.self)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let message: String
            if detail.contains("Permission denied") {
                message = "SSH login was rejected. Check the SSH user and key. \(detail)"
            } else if detail.contains("Host key verification failed") {
                message = "Trust this host once in Terminal with ssh, then retry. \(detail)"
            } else if detail.contains("not recognized") || detail.contains("not found") {
                message = "The selected Python or WSL command is unavailable. \(detail)"
            } else {
                message = detail.isEmpty ? "Remote command exited \(process.terminationStatus)." : detail
            }
            throw SSHRemoteUsageError.commandFailed(message)
        }
        return output
    }
}
