import SwiftUI

struct RemoteDevicesSettingsSection: View {
    let store: RemoteUsageDeviceStore
    @AppStorage(DensitySetting.key) private var density = DensitySetting.regular
    @State private var editor: EditorSession?
    @State private var pendingRemoval: RemoteUsageDevice?

    private struct EditorSession: Identifiable {
        let id = UUID()
        let device: RemoteUsageDevice?
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Remote Devices").font(.caption.weight(.semibold))
                Spacer()
                if editor == nil && !store.devices.isEmpty {
                    Text("\(store.devices.count)").font(.caption.monospacedDigit())
                }
            }
            .foregroundStyle(.secondary).padding(.horizontal, 8)
            if let editor {
                RemoteDeviceEditor(store: store, device: editor.device) { self.editor = nil }
                    .id(editor.id)
            } else {
                deviceList
                Text("Claude and Codex history from your other computers. Live account limits still come from this Mac.")
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true).padding(.horizontal, 8)
            }
        }
        .confirmationDialog(
            "Remove \(pendingRemoval?.name ?? "Device")?",
            isPresented: Binding(get: { pendingRemoval != nil }, set: { if !$0 { pendingRemoval = nil } })
        ) {
            Button("Remove Device", role: .destructive) {
                if let pendingRemoval { store.remove(pendingRemoval.id) }
                pendingRemoval = nil
            }
            Button("Cancel", role: .cancel) { pendingRemoval = nil }
        } message: {
            Text("Removes its settings and saved history from this Mac. The remote computer is unchanged.")
        }
    }

    private var deviceList: some View {
        VStack(spacing: 0) {
            if store.devices.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Bring Your Other Computers", systemImage: "desktopcomputer")
                        .font(.body.weight(.medium))
                    Text("Add a device over SSH to include its Claude and Codex history here.")
                        .font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading).padding(12)
            } else {
                ForEach(store.devices) { device in
                    RemoteDeviceRow(
                        device: device, lastUpdated: store.lastUpdated[device.id],
                        error: store.errors[device.id], isRefreshing: store.isRefreshing(device.id),
                        historyIsEmpty: store.historyIsEmpty(device.id),
                        onEdit: { editor = EditorSession(device: device) },
                        onRefresh: { Task { await store.refresh(device.id) } },
                        onRemove: { pendingRemoval = device }
                    )
                    Divider().padding(.leading, 12)
                }
            }
            Button { editor = EditorSession(device: nil) } label: {
                Label("Add Device", systemImage: "plus")
                    .font(.body.weight(.medium)).foregroundStyle(Color.accentColor)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12).padding(.vertical, density.controlRowPadding + 2)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain).accessibilityLabel("Add Remote Device")
        }
        .cardSurface()
    }
}

/// Value inputs keep refreshes from invalidating every row or an open editor.
struct RemoteDeviceRow: View {
    let device: RemoteUsageDevice
    let lastUpdated: Date?
    let error: String?
    let isRefreshing: Bool
    let historyIsEmpty: Bool
    let onEdit: () -> Void
    let onRefresh: () -> Void
    let onRemove: () -> Void
    @AppStorage(DensitySetting.key) private var density = DensitySetting.regular
    @State private var showErrorDetails = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: device.platform == .macOS ? "laptopcomputer" : "desktopcomputer")
                    .font(.body).foregroundStyle(.secondary).frame(width: 20, height: 24)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 3) {
                    Text(device.name).font(.body.weight(.semibold)).fixedSize(horizontal: false, vertical: true)
                    Text(endpoint).font(.caption).foregroundStyle(.secondary)
                        .lineLimit(1).truncationMode(.middle)
                    if device.platform == .wsl {
                        Text("WSL · \(device.wslDistribution ?? "Default distribution")\(device.wslUser.map { " · \($0)" } ?? "")")
                            .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    } else {
                        Text(device.platform.rawValue).font(.caption).foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Menu {
                    Button("Edit Device", systemImage: "pencil", action: onEdit).disabled(isRefreshing)
                    Divider()
                    Button("Remove Device", systemImage: "trash", role: .destructive, action: onRemove)
                } label: {
                    Image(systemName: "ellipsis").frame(width: 28, height: 28).contentShape(Rectangle())
                }
                .menuIndicator(.hidden).buttonStyle(.plain)
                .accessibilityLabel("Actions for \(device.name)")
            }
            HStack(spacing: 6) {
                if isRefreshing {
                    ProgressView().controlSize(.mini)
                    Text("Importing History…")
                } else if !device.enabled {
                    Label("Paused", systemImage: "pause.circle")
                } else if error != nil {
                    Label("Import Failed", systemImage: "exclamationmark.triangle").foregroundStyle(Theme.notice)
                } else if lastUpdated != nil {
                    Label(historyIsEmpty ? "No History Found" : "History Imported",
                          systemImage: historyIsEmpty ? "tray" : "checkmark.circle")
                } else {
                    Label("Not Imported Yet", systemImage: "clock")
                }
                Spacer(minLength: 4)
                Button(error == nil ? "Refresh" : "Retry", action: onRefresh)
                    .buttonStyle(.borderless).disabled(isRefreshing || !device.enabled)
                    .accessibilityLabel("\(error == nil ? "Refresh" : "Retry") history for \(device.name)")
            }
            .font(.caption.weight(.medium))
            if let lastUpdated {
                Text("Last imported \(lastUpdated.formatted(date: .abbreviated, time: .shortened))")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            if let error {
                DisclosureGroup(isExpanded: $showErrorDetails) {
                    Text(error).textSelection(.enabled).font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true).padding(.top, 4)
                } label: {
                    Text(lastUpdated == nil ? "Saved. Retry or edit the connection." : "Showing saved history. View error.")
                        .font(.caption)
                }
                .font(.caption)
            } else if lastUpdated != nil && historyIsEmpty {
                Text("No Claude or Codex records were found for this user.")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 12).padding(.vertical, density.controlRowPadding + 3)
    }

    private var endpoint: String {
        "\(device.sshUser.map { "\($0)@" } ?? "")\(device.host)\(device.sshPort.map { ":\($0)" } ?? "")"
    }
}
