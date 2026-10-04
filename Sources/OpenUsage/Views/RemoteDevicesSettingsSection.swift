import SwiftUI

struct RemoteDevicesSettingsSection: View {
    @Bindable var store: RemoteUsageDeviceStore
    @AppStorage(DensitySetting.key) private var density = DensitySetting.regular
    @State private var name = ""
    @State private var host = ""
    @State private var sshUser = ""
    @State private var sshPort = ""
    @State private var wslDistribution = ""
    @State private var wslUser = ""
    @State private var platform: RemoteUsageDevice.Platform = .wsl
    @State private var addError: String?
    @State private var testResult: String?
    @State private var editingID: String?
    @State private var busy = false

    var body: some View {
        VStack(alignment: .leading, spacing: density.headerToCardSpacing) {
            Text("Remote Devices")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
            VStack(alignment: .leading, spacing: 9) {
                Text("Read Claude and Codex usage over SSH. Only daily summaries are saved on this Mac.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextField("Device name", text: $name)
                    .textFieldStyle(.roundedBorder)
                TextField("SSH host or IP address", text: $host)
                    .textFieldStyle(.roundedBorder)
                HStack {
                    TextField("SSH username", text: $sshUser)
                    TextField("Port (22)", text: $sshPort)
                        .frame(width: 75)
                }
                .textFieldStyle(.roundedBorder)
                Text("Leave SSH username blank to use your SSH config or Mac username.")
                    .font(.caption2).foregroundStyle(.secondary)
                if platform == .wsl {
                    HStack {
                        TextField("WSL distribution (default)", text: $wslDistribution)
                        TextField("Linux username (default)", text: $wslUser)
                    }
                    .textFieldStyle(.roundedBorder)
                }
                HStack {
                    Picker("System", selection: $platform) {
                        ForEach(RemoteUsageDevice.Platform.allCases, id: \.self) { option in
                            Text(option == .wsl ? "WSL" : option.rawValue).tag(option)
                        }
                    }
                    Button(editingID == nil ? "Add Device" : "Save Changes") {
                        Task {
                            busy = true
                            defer { busy = false }
                            do {
                                let device = try candidate()
                                if editingID == nil { try await store.add(device) }
                                else { try await store.update(device) }
                                resetForm()
                                addError = nil
                            } catch {
                                addError = error.localizedDescription
                            }
                        }
                    }
                    .disabled(busy || name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                              || host.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    Button("Test Connection") {
                        Task {
                            busy = true
                            defer { busy = false }
                            do {
                                testResult = "Connected: \(try await store.test(candidate()))"
                                addError = nil
                            } catch {
                                testResult = nil
                                addError = error.localizedDescription
                            }
                        }
                    }
                    .disabled(busy || name.isEmpty || host.isEmpty)
                    if editingID != nil {
                        Button("Cancel") { resetForm() }
                    }
                }
                if let testResult {
                    Text(testResult).font(.caption2).foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
                if let addError {
                    Text(addError).font(.caption).foregroundStyle(Theme.notice)
                }
                if !store.devices.isEmpty {
                    Divider()
                    ForEach(store.devices) { device in
                        HStack(spacing: 8) {
                            Image(systemName: "desktopcomputer")
                                .foregroundStyle(.secondary)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(device.name).lineLimit(1)
                                Text("\(device.sshUser.map { "\($0)@" } ?? "")\(device.host)\(device.sshPort.map { ":\($0)" } ?? "") · \(device.platform.rawValue)")
                                    .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                                if let error = store.errors[device.id] {
                                    Text(error).font(.caption2).foregroundStyle(Theme.notice)
                                        .fixedSize(horizontal: false, vertical: true)
                                } else if let updated = store.lastUpdated[device.id] {
                                    Text("Updated \(updated.formatted(date: .abbreviated, time: .shortened))")
                                        .font(.caption2).foregroundStyle(.secondary)
                                }
                            }
                            Spacer(minLength: 2)
                            Button { edit(device) } label: {
                                Image(systemName: "pencil")
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Edit \(device.name)")
                            Button { Task { await store.refresh(device.id) } } label: {
                                Image(systemName: "arrow.clockwise")
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Refresh \(device.name)")
                            Button { store.remove(device.id) } label: {
                                Image(systemName: "trash")
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Remove \(device.name)")
                        }
                    }
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .cardSurface()
        }
    }

    private func candidate() throws -> RemoteUsageDevice {
        func trimmed(_ value: String) -> String { value.trimmingCharacters(in: .whitespacesAndNewlines) }
        func optional(_ value: String) -> String? { trimmed(value).isEmpty ? nil : trimmed(value) }
        let portText = trimmed(sshPort)
        guard portText.isEmpty || Int(portText) != nil else { throw SSHRemoteUsageError.invalidConfiguration }
        return RemoteUsageDevice(
            id: editingID ?? "ssh-\(UUID().uuidString.lowercased())", name: trimmed(name),
            host: trimmed(host), platform: platform,
            sshUser: optional(sshUser), sshPort: portText.isEmpty ? nil : Int(portText),
            wslDistribution: platform == .wsl ? optional(wslDistribution) : nil,
            wslUser: platform == .wsl ? optional(wslUser) : nil
        )
    }

    private func edit(_ device: RemoteUsageDevice) {
        editingID = device.id
        name = device.name
        host = device.host
        sshUser = device.sshUser ?? ""
        sshPort = device.sshPort.map(String.init) ?? ""
        wslDistribution = device.wslDistribution ?? ""
        wslUser = device.wslUser ?? ""
        platform = device.platform
        addError = nil
        testResult = nil
    }

    private func resetForm() {
        editingID = nil
        name = ""
        host = ""
        sshUser = ""
        sshPort = ""
        wslDistribution = ""
        wslUser = ""
        addError = nil
        testResult = nil
    }
}
