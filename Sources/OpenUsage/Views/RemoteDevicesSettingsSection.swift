import SwiftUI

struct RemoteDevicesSettingsSection: View {
    @Bindable var store: RemoteUsageDeviceStore
    @AppStorage(DensitySetting.key) private var density = DensitySetting.regular
    @State private var name = ""
    @State private var host = ""
    @State private var platform: RemoteUsageDevice.Platform = .wsl
    @State private var addError: String?

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
                TextField("SSH host alias", text: $host)
                    .textFieldStyle(.roundedBorder)
                HStack {
                    Picker("System", selection: $platform) {
                        ForEach(RemoteUsageDevice.Platform.allCases, id: \.self) { option in
                            Text(option == .wsl ? "WSL" : option.rawValue).tag(option)
                        }
                    }
                    Button("Add Device") {
                        Task {
                            do {
                                try await store.add(name: name, host: host, platform: platform)
                                name = ""
                                host = ""
                                addError = nil
                            } catch {
                                addError = error.localizedDescription
                            }
                        }
                    }
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                              || host.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
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
                                Text("\(device.host) · \(device.platform.rawValue)")
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
}
