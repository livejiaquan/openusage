import Foundation
import Observation

/// User-managed SSH sources. Configuration and last-good daily summaries are small JSON values in
/// this Mac's preferences; raw remote JSONL and exported per-event metadata are never persisted here.
@MainActor
@Observable
final class RemoteUsageDeviceStore {
    private static let devicesKey = "openusage.remote.devices.v1"
    private static let summariesKey = "openusage.remote.summaries.v1"

    private let defaults: UserDefaults
    private let dataStore: WidgetDataStore
    private let client: SSHRemoteUsageClient
    private var documents: [String: UsageHistoryDocument]
    private var refreshingIDs: Set<String> = []

    private(set) var devices: [RemoteUsageDevice]
    private(set) var errors: [String: String] = [:]
    private(set) var lastUpdated: [String: Date] = [:]
    var isRefreshing: Bool { !refreshingIDs.isEmpty }

    init(dataStore: WidgetDataStore, defaults: UserDefaults = .standard,
         client: SSHRemoteUsageClient = SSHRemoteUsageClient()) {
        self.dataStore = dataStore
        self.defaults = defaults
        self.client = client
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let loadedDevices = (defaults.data(forKey: Self.devicesKey)
            .flatMap { try? decoder.decode([RemoteUsageDevice].self, from: $0) }) ?? []
        self.devices = loadedDevices
        let saved = (defaults.data(forKey: Self.summariesKey)
            .flatMap { try? decoder.decode([UsageHistoryDocument].self, from: $0) }) ?? []
        let valid = UsageHistoryDocument.newestByDevice(saved).compactMap { document -> (String, UsageHistoryDocument)? in
            guard (try? document.validate()) != nil else { return nil }
            guard loadedDevices.contains(where: { $0.id == document.deviceID }) else { return nil }
            return (document.deviceID, document)
        }
        self.documents = Dictionary(uniqueKeysWithValues: valid)
        self.lastUpdated = documents.mapValues(\.updatedAt)
        dataStore.setRemoteHistoryDocuments(Array(documents.values))
    }

    func add(name: String, host: String, platform: RemoteUsageDevice.Platform) async throws {
        let device = RemoteUsageDevice(name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                                       host: host.trimmingCharacters(in: .whitespacesAndNewlines),
                                       platform: platform)
        guard device.isValid else { throw SSHRemoteUsageError.invalidHost }
        guard !devices.contains(where: { $0.host == device.host && $0.platform == device.platform }) else {
            throw SSHRemoteUsageError.commandFailed("This SSH host and platform are already added.")
        }
        devices.append(device)
        persistDevices()
        await refresh(device.id)
    }

    func remove(_ id: String) {
        devices.removeAll { $0.id == id }
        documents.removeValue(forKey: id)
        errors.removeValue(forKey: id)
        lastUpdated.removeValue(forKey: id)
        persistDevices()
        persistDocuments()
        dataStore.setRemoteHistoryDocuments(Array(documents.values))
    }

    func removeAll() {
        devices = []
        documents = [:]
        errors = [:]
        lastUpdated = [:]
        persistDevices()
        persistDocuments()
        dataStore.setRemoteHistoryDocuments([])
    }

    func refreshAll() async {
        for device in devices where device.enabled {
            await refresh(device.id)
        }
    }

    func refresh(_ id: String) async {
        guard let device = devices.first(where: { $0.id == id && $0.enabled }),
              refreshingIDs.insert(id).inserted
        else { return }
        defer { refreshingIDs.remove(id) }
        do {
            let document = try await client.fetch(device)
            try document.validate()
            // A device removed while SSH was in flight must not reappear in the combined view.
            guard devices.contains(where: { $0.id == id && $0.enabled }) else { return }
            documents[id] = document
            lastUpdated[id] = document.updatedAt
            errors[id] = nil
            persistDocuments()
            dataStore.setRemoteHistoryDocuments(Array(documents.values))
        } catch {
            errors[id] = error.localizedDescription
            AppLog.warn(.config, "remote usage \(device.name): \(error.localizedDescription)")
        }
    }

    private func persistDevices() {
        if let data = try? JSONEncoder().encode(devices) {
            defaults.set(data, forKey: Self.devicesKey)
        }
    }

    private func persistDocuments() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        if let data = try? encoder.encode(Array(documents.values)) {
            defaults.set(data, forKey: Self.summariesKey)
        }
    }
}
