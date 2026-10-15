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
                        hiddenProviders: store.hiddenProviders(device.id),
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
    let hiddenProviders: [String]
    let onEdit: () -> Void
    let onRefresh: () -> Void
    let onRemove: () -> Void
    @AppStorage(DensitySetting.key) private var density = DensitySetting.regular
    @State private var showErrorDetails = false

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 8) {
                Circle().fill(statusColor).frame(width: 8, height: 8).accessibilityHidden(true)
                Text(device.name).font(.body.weight(.semibold)).lineLimit(1).truncationMode(.tail)
                Spacer(minLength: 4)
                if isRefreshing {
                    ProgressView().controlSize(.mini).frame(width: 24, height: 24)
                        .accessibilityLabel("Importing history for \(device.name)")
                } else {
                    Button(action: onRefresh) {
                        Image(systemName: "arrow.clockwise").frame(width: 24, height: 24).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain).foregroundStyle(.secondary).disabled(!device.enabled)
                    .accessibilityLabel("\(error == nil ? "Refresh" : "Retry") history for \(device.name)")
                }
                Menu {
                    Button("Edit Device", systemImage: "pencil", action: onEdit).disabled(isRefreshing)
                    Divider()
                    Button("Remove Device", systemImage: "trash", role: .destructive, action: onRemove)
                } label: {
                    Image(systemName: "ellipsis").frame(width: 24, height: 24).contentShape(Rectangle())
                }
                .menuIndicator(.hidden).buttonStyle(.plain)
                .accessibilityLabel("Actions for \(device.name)")
            }
            Group {
                Text(summary).lineLimit(1).truncationMode(.middle).foregroundStyle(.secondary)
                statusLine
                if let error, showErrorDetails {
                    Text(error).textSelection(.enabled).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true).padding(.top, 2)
                }
                if !hiddenProviders.isEmpty {
                    Label(hiddenProvidersNotice, systemImage: "eye.slash").foregroundStyle(Theme.notice)
                        .fixedSize(horizontal: false, vertical: true).padding(.top, 2)
                }
            }
            .font(.caption).padding(.leading, 16)
        }
        .padding(.horizontal, 12).padding(.vertical, density.controlRowPadding + 3)
    }

    @ViewBuilder
    private var statusLine: some View {
        if isRefreshing {
            Text("Importing history…").foregroundStyle(.secondary)
        } else if !device.enabled {
            Text("Paused").foregroundStyle(.secondary)
        } else if error != nil {
            HStack(spacing: 4) {
                TimelineView(.periodic(from: .now, by: 60)) { context in
                    Text(lastUpdated.map { "Import failed · showing data from \(Self.age($0, now: context.date))" }
                         ?? "Import failed")
                        .foregroundStyle(Theme.notice).lineLimit(1)
                }
                Button(showErrorDetails ? "Hide" : "Details") { showErrorDetails.toggle() }
                    .buttonStyle(.borderless).fixedSize()
                    .accessibilityLabel(showErrorDetails ? "Hide error details" : "Show error details")
            }
        } else if let lastUpdated {
            TimelineView(.periodic(from: .now, by: 60)) { context in
                Text("Updated \(Self.age(lastUpdated, now: context.date))"
                     + (historyIsEmpty ? " · no Claude or Codex logs found" : ""))
                    .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        } else {
            Text("Not imported yet").foregroundStyle(.secondary)
        }
    }

    private var statusColor: Color {
        if isRefreshing || !device.enabled || lastUpdated == nil && error == nil { return .secondary.opacity(0.5) }
        if error != nil || !hiddenProviders.isEmpty { return Color(nsColor: .systemOrange) }
        return historyIsEmpty ? .secondary.opacity(0.5) : Color(nsColor: .systemGreen)
    }

    private var summary: String {
        let endpoint = "\(device.sshUser.map { "\($0)@" } ?? "")\(device.host)\(device.sshPort.map { ":\($0)" } ?? "")"
        let system: String
        switch device.platform {
        case .wsl:
            system = "WSL \(device.wslDistribution ?? "default")\(device.wslUser.map { " · \($0)" } ?? "")"
        case .linux, .windows, .macOS:
            system = device.platform.rawValue
        }
        return "\(endpoint) · \(system)"
    }

    private var hiddenProvidersNotice: String {
        let names = hiddenProviders.formatted(.list(type: .and))
        let verb = hiddenProviders.count == 1 ? "isn't" : "aren't"
        return "\(names) \(verb) counted on the dashboard. This Mac has more than one account for "
            + (hiddenProviders.count == 1 ? "it" : "them") + ", so this device's history can't be matched to one."
    }

    /// Same compact age as iCloud Sync's device rows.
    static func age(_ date: Date, now: Date) -> String {
        let seconds = max(0, now.timeIntervalSince(date))
        if seconds < 60 { return "just now" }
        if seconds < 3_600 { return "\(max(1, Int(seconds / 60)))m ago" }
        if seconds < 86_400 { return "\(max(1, Int(seconds / 3_600)))h ago" }
        return "\(max(1, Int(seconds / 86_400)))d ago"
    }
}
