import Foundation

enum SSHRemoteUsageError: Error, LocalizedError {
    case invalidHost
    case missingExporter
    case commandFailed(String)
    case oversizedResponse
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .invalidHost: "Enter an SSH host alias or DNS name."
        case .missingExporter: "The remote usage exporter is missing from this build."
        case .commandFailed(let detail): "SSH import failed: \(detail)"
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
        guard device.isValid else { throw SSHRemoteUsageError.invalidHost }
        guard let url = Bundle.openUsageResources.url(forResource: "remote_usage_export", withExtension: "py")
        else { throw SSHRemoteUsageError.missingExporter }
        let script = try Data(contentsOf: url)
        let output = try runSSH(host: device.host, command: device.platform.command, input: script)
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

    private func runSSH(host: String, command: String, input: Data) throws -> Data {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ssh")
        process.arguments = [
            "-T", "-o", "BatchMode=yes", "-o", "StrictHostKeyChecking=yes",
            "-o", "ConnectTimeout=10", "-o", "ServerAliveInterval=10",
            "-o", "ServerAliveCountMax=3", host, command
        ]
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
            throw SSHRemoteUsageError.commandFailed(detail.isEmpty ? "Remote command exited \(process.terminationStatus)." : detail)
        }
        return output
    }
}
