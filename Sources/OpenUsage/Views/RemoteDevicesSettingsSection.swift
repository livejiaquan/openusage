import SwiftUI

struct RemoteDevicesSettingsSection: View {
    @Bindable var store: RemoteUsageDeviceStore
    @AppStorage(DensitySetting.key) private var density = DensitySetting.regular
    @State private var isEditing = false
    @State private var editingID: String?
    @State private var name = ""
    @State private var host = ""
    @State private var sshUser = ""
    @State private var sshPort = ""
    @State private var wslDistribution = ""
    @State private var wslUser = ""
    @State private var platform: RemoteUsageDevice.Platform = .wsl
    @State private var showSSHOptions = false
    @State private var showWSLOptions = false
    @State private var formError: String?
    @State private var testResult: String?
    @State private var busy = false
    @State private var pendingRemoval: RemoteUsageDevice?

    var body: some View {
        VStack(alignment: .leading, spacing: density.headerToCardSpacing) {
            Text("Remote Devices")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
            if isEditing { editorCard }
            else { deviceListCard }
            Text("Only daily usage summaries are saved on this Mac.")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
        }
        .confirmationDialog(
            "Remove \(pendingRemoval?.name ?? "Device")?",
            isPresented: Binding(
                get: { pendingRemoval != nil },
                set: { if !$0 { pendingRemoval = nil } }
            )
        ) {
            Button("Remove Device", role: .destructive) {
                if let pendingRemoval { store.remove(pendingRemoval.id) }
                pendingRemoval = nil
            }
            Button("Cancel", role: .cancel) { pendingRemoval = nil }
        } message: {
            Text("Its saved usage summary will be removed from this Mac.")
        }
    }

    private var deviceListCard: some View {
        VStack(spacing: 0) {
            if store.devices.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("No Remote Devices")
                        .font(.body.weight(.medium))
                    Text("Connect a Mac, Windows, Linux, or WSL device over SSH to include its Claude and Codex history.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
            } else {
                ForEach(Array(store.devices.enumerated()), id: \.element.id) { index, device in
                    if index > 0 { Divider() }
                    deviceRow(device)
                }
            }
            Divider()
            Button { beginAdding() } label: {
                HStack(spacing: 8) {
                    Image(systemName: "plus").frame(width: 18)
                    Text("Add Device")
                    Spacer()
                }
                .contentShape(Rectangle())
                .padding(.horizontal, 12)
                .padding(.vertical, density.controlRowPadding)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Add Remote Device")
        }
        .cardSurface()
    }

    private func deviceRow(_ device: RemoteUsageDevice) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "desktopcomputer")
                .foregroundStyle(.secondary)
                .frame(width: 18)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 2) {
                Text(device.name)
                    .font(.body.weight(.medium))
                    .lineLimit(1)
                Text("\(device.platform == .wsl ? "WSL" : device.platform.rawValue) · \(device.sshUser.map { "\($0)@" } ?? "")\(device.host)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                if let error = store.errors[device.id] {
                    Text(error)
                        .font(.caption2)
                        .foregroundStyle(Theme.notice)
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                } else if let updated = store.lastUpdated[device.id] {
                    Text("Updated \(updated.formatted(date: .abbreviated, time: .shortened))")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Waiting for first update")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Menu {
                Button("Edit", systemImage: "pencil") { beginEditing(device) }
                Button("Refresh", systemImage: "arrow.clockwise") {
                    Task { await store.refresh(device.id) }
                }
                Divider()
                Button("Remove", systemImage: "trash", role: .destructive) {
                    pendingRemoval = device
                }
            } label: {
                Image(systemName: "ellipsis")
                    .frame(width: 20, height: 20)
                    .contentShape(Rectangle())
            }
            .menuIndicator(.hidden)
            .buttonStyle(.plain)
            .accessibilityLabel("Actions for \(device.name)")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, density.controlRowPadding)
    }

    private var editorCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(editingID == nil ? "Add Device" : "Edit Device")
                    .font(.body.weight(.semibold))
                Spacer()
                Button("Cancel") { resetForm() }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
            }
            Divider()
            field("Name", placeholder: "Lab computer", text: $name)
            field("SSH Host or IP", placeholder: "lab or 100.115.179.72", text: $host)
            field("SSH Username", placeholder: "Use SSH config", text: $sshUser)
            Picker("System", selection: $platform) {
                ForEach(RemoteUsageDevice.Platform.allCases, id: \.self) { option in
                    Text(option == .wsl ? "Windows WSL" : option.rawValue).tag(option)
                }
            }
            if platform == .wsl {
                Text("Connects to Windows first, then reads the selected WSL user's logs.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                DisclosureGroup("WSL Options", isExpanded: $showWSLOptions) {
                    VStack(alignment: .leading, spacing: 10) {
                        field("Distribution", placeholder: "Default", text: $wslDistribution)
                        field("Linux Username", placeholder: "Default", text: $wslUser)
                    }
                    .padding(.top, 8)
                }
                .font(.caption)
            }
            DisclosureGroup("SSH Options", isExpanded: $showSSHOptions) {
                field("Port", placeholder: "22", text: $sshPort)
                    .padding(.top, 8)
            }
            .font(.caption)
            if let testResult {
                Label(testResult, systemImage: "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.green)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let formError {
                Label(formError, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(Theme.notice)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Divider()
            HStack {
                Button("Test Connection") { testConnection() }
                    .disabled(busy || !hasRequiredFields)
                Spacer(minLength: 4)
                Button(editingID == nil ? "Add" : "Save") { save() }
                    .buttonStyle(.borderedProminent)
                    .disabled(busy || !hasRequiredFields)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
    }

    private func field(_ label: String, placeholder: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            TextField(placeholder, text: text)
                .textFieldStyle(.roundedBorder)
        }
    }

    private var hasRequiredFields: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !host.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func testConnection() {
        Task {
            busy = true
            defer { busy = false }
            do {
                let response = try await store.test(candidate())
                let parts = response.components(separatedBy: " | ")
                testResult = parts.count == 3 ? "Connected as \(parts[1]) · \(parts[2])" : "Connected"
                formError = nil
            } catch {
                testResult = nil
                formError = error.localizedDescription
            }
        }
    }

    private func save() {
        Task {
            busy = true
            defer { busy = false }
            do {
                let device = try candidate()
                if editingID == nil { try await store.add(device) }
                else { try await store.update(device) }
                resetForm()
            } catch {
                formError = error.localizedDescription
            }
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

    private func beginAdding() {
        resetForm()
        isEditing = true
    }

    private func beginEditing(_ device: RemoteUsageDevice) {
        editingID = device.id
        name = device.name
        host = device.host
        sshUser = device.sshUser ?? ""
        sshPort = device.sshPort.map(String.init) ?? ""
        wslDistribution = device.wslDistribution ?? ""
        wslUser = device.wslUser ?? ""
        platform = device.platform
        showSSHOptions = device.sshPort != nil
        showWSLOptions = device.wslDistribution != nil || device.wslUser != nil
        formError = nil
        testResult = nil
        isEditing = true
    }

    private func resetForm() {
        isEditing = false
        editingID = nil
        name = ""
        host = ""
        sshUser = ""
        sshPort = ""
        wslDistribution = ""
        wslUser = ""
        showSSHOptions = false
        showWSLOptions = false
        formError = nil
        testResult = nil
    }
}
