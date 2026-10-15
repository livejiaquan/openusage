import AppKit
import SwiftUI

struct RemoteDeviceEditor: View {
    let store: RemoteUsageDeviceStore
    let onFinish: () -> Void
    private let isNew: Bool
    @State private var draft: RemoteUsageDeviceDraft
    @State private var showSSHOptions: Bool
    @State private var showWSLOptions: Bool
    @State private var showSetupGuide: Bool
    @State private var copiedSSHCommand = false
    @State private var touchedFields: Set<RemoteUsageDeviceDraft.Field> = []
    @State private var attemptedSubmit = false
    @State private var operation: Operation?
    @State private var probeResult: String?
    @State private var operationError: String?
    @FocusState private var focusedField: RemoteUsageDeviceDraft.Field?
    private enum Operation { case testing, saving }

    init(store: RemoteUsageDeviceStore, device: RemoteUsageDevice? = nil, onFinish: @escaping () -> Void) {
        self.store = store
        self.onFinish = onFinish
        isNew = device == nil
        // Each editor session owns a fresh draft; no field is persisted before Save.
        _draft = State(initialValue: RemoteUsageDeviceDraft(device: device))
        _showSSHOptions = State(initialValue: device?.sshPort != nil)
        _showWSLOptions = State(initialValue: device?.wslDistribution != nil || device?.wslUser != nil)
        _showSetupGuide = State(initialValue: device == nil)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(isNew ? "Add Device" : "Edit Device").font(.body.weight(.semibold))
                Spacer()
                Button("Cancel", action: onFinish).buttonStyle(.borderless).disabled(operation != nil)
            }
            field(.name, "Device Name", placeholder: "Lab Computer", text: $draft.name)
            // The system comes first: it decides what the username below means and where logs are read.
            HStack {
                Text("System").font(.caption.weight(.medium))
                Spacer(minLength: 8)
                Picker("System", selection: $draft.platform) {
                    ForEach(Self.platformOrder, id: \.self) { platform in
                        Text(platform == .wsl ? "Windows + WSL" : platform.rawValue).tag(platform)
                    }
                }
                .labelsHidden().pickerStyle(.menu).fixedSize().disabled(operation != nil)
            }
            help(systemHelp)
            Divider()
            field(.host, "Host or IP Address", placeholder: "lab-server or 192.168.1.20", text: $draft.host)
            field(.sshUser, windowsSSH ? "Windows Username" : "SSH Username",
                  placeholder: "From SSH config", text: $draft.sshUser, optional: true)
            DisclosureGroup(isExpanded: $showSSHOptions) {
                field(.sshPort, "Port", placeholder: "From SSH config, otherwise 22", text: $draft.sshPort, optional: true)
                    .padding(.top, 8)
            } label: {
                Text("Advanced SSH")
                    .accessibilityHint(showSSHOptions
                        ? "Contains the optional SSH port setting."
                        : "Expand to set a custom SSH port.")
            }
            .font(.caption.weight(.medium))
            if draft.platform == .wsl {
                DisclosureGroup(isExpanded: $showWSLOptions) {
                    VStack(alignment: .leading, spacing: 10) {
                        field(.wslDistribution, "Distribution", placeholder: "Windows default", text: $draft.wslDistribution, optional: true)
                        field(.wslUser, "Linux Username", placeholder: "Distribution default", text: $draft.wslUser, optional: true)
                        help("The Linux account whose Claude and Codex logs you want to import.")
                    }
                    .padding(.top, 8)
                } label: {
                    Text("WSL Environment")
                        .accessibilityHint(showWSLOptions
                            ? "Contains the optional WSL distribution and Linux username settings."
                            : "Expand to set a WSL distribution and Linux username.")
                }
                .font(.caption.weight(.medium))
            }
            Divider()
            setupGuide
            feedback
            actions
            help("Saving imports history. Uses your SSH keys; only daily summaries stay on this Mac.")
        }
        .padding(12).cardSurface()
        .onChange(of: draft.connectionIdentity) { probeResult = nil; operationError = nil }
        .onChange(of: focusedField) { old, _ in if let old { touchedFields.insert(old) } }
        .task { focusedField = .name }
    }

    private var windowsSSH: Bool { draft.platform == .wsl || draft.platform == .windows }

    private static let platformOrder: [RemoteUsageDevice.Platform] = [.linux, .macOS, .windows, .wsl]

    private var systemHelp: String {
        switch draft.platform {
        case .linux, .macOS: "Reads the SSH account's Claude and Codex logs."
        case .windows: "Reads the Windows account's logs with Python 3 (py -3)."
        case .wsl: "SSH logs in to Windows; logs are read inside WSL."
        }
    }

    /// What has to be true before the first import; the host-key step is the one people miss.
    private var setupGuide: some View {
        DisclosureGroup(isExpanded: $showSetupGuide) {
            VStack(alignment: .leading, spacing: 6) {
                help("1. Set up SSH key login to this device. Passwords aren't supported.")
                help("2. Connect once in Terminal so this Mac trusts its host key:")
                HStack(spacing: 6) {
                    Text(sshCommand).font(.caption.monospaced()).textSelection(.enabled)
                        .lineLimit(1).truncationMode(.middle)
                    Spacer(minLength: 4)
                    Button(copiedSSHCommand ? "Copied" : "Copy") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(sshCommand, forType: .string)
                        copiedSSHCommand = true
                    }
                    .buttonStyle(.borderless).font(.caption).fixedSize()
                    .accessibilityLabel("Copy SSH command")
                }
                .padding(6).background(.fill.quaternary, in: RoundedRectangle(cornerRadius: 6))
                help(draft.platform == .windows || draft.platform == .wsl
                     ? "3. Install Python 3 \(draft.platform == .wsl ? "inside WSL" : "on Windows")."
                     : "3. Make sure python3 is installed on the device.")
            }
            .padding(.top, 6)
        } label: {
            Text("Before You Start")
        }
        .font(.caption.weight(.medium))
        .onChange(of: sshCommand) { copiedSSHCommand = false }
    }

    private var sshCommand: String {
        let host = draft.host.trimmingCharacters(in: .whitespacesAndNewlines)
        let user = draft.sshUser.trimmingCharacters(in: .whitespacesAndNewlines)
        let port = draft.sshPort.trimmingCharacters(in: .whitespacesAndNewlines)
        return "ssh " + (port.isEmpty ? "" : "-p \(port) ") + (user.isEmpty ? "" : "\(user)@")
            + (host.isEmpty ? "your-host" : host) + " exit"
    }

    private func help(_ text: String) -> some View {
        Text(text).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
    }

    private func field(_ field: RemoteUsageDeviceDraft.Field, _ label: String,
                       placeholder: String, text: Binding<String>, optional: Bool = false) -> some View {
        let error = attemptedSubmit || touchedFields.contains(field) ? draft.validationErrors[field] : nil
        return VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label).font(.caption.weight(.medium))
                if optional {
                    Spacer()
                    Text("Optional").font(.caption).foregroundStyle(.secondary)
                }
            }
            TextField(placeholder, text: text).textFieldStyle(.roundedBorder)
                .autocorrectionDisabled(field != .name)
                .focused($focusedField, equals: field).disabled(operation != nil)
                .accessibilityLabel(label)
                .accessibilityHint(error ?? (optional ? "Leave blank to use the default." : "Required."))
            if let error {
                Label(error, systemImage: "exclamationmark.circle").font(.caption).foregroundStyle(Theme.notice)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    @ViewBuilder
    private var feedback: some View {
        if let operation {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text(operation == .testing ? "Testing connection…" : "Saving and importing history…").font(.caption)
            }
            .accessibilityElement(children: .combine)
        } else if let probeResult {
            VStack(alignment: .leading, spacing: 4) {
                Label("Connection Ready", systemImage: "checkmark.circle.fill")
                    .font(.caption.weight(.medium)).foregroundStyle(Theme.positive)
                help(probeResult)
            }
        } else if let operationError {
            Label(operationError, systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(Theme.notice)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var actions: some View {
        HStack(spacing: 8) {
            Button("Test Connection") { testConnection() }.buttonStyle(.bordered)
                .accessibilityHint("Checks SSH login and Python on the device. Saving also imports history.")
            Spacer(minLength: 0)
            Button(isNew ? "Add Device" : "Save Changes") { save() }.buttonStyle(.borderedProminent)
                .accessibilityHint("Saves this device and imports its usage history.")
        }
        .disabled(operation != nil).controlSize(.regular)
    }

    private func validatedDevice() -> RemoteUsageDevice? {
        attemptedSubmit = true
        operationError = nil
        if let first = RemoteUsageDeviceDraft.Field.allCases.first(where: { draft.validationErrors[$0] != nil }) {
            if first == .sshPort { showSSHOptions = true }
            if first == .wslUser || first == .wslDistribution { showWSLOptions = true }
            focusedField = first
            return nil
        }
        do { return try draft.makeDevice() }
        catch { operationError = error.localizedDescription; return nil }
    }

    private func testConnection() {
        guard operation == nil, let device = validatedDevice() else { return }
        operation = .testing
        probeResult = nil
        Task {
            defer { operation = nil }
            do {
                let response = try await store.test(device)
                let parts = response.components(separatedBy: " | ")
                probeResult = parts.count == 3 ? "\(parts[1]) · \(parts[2])" : response
            } catch { operationError = error.localizedDescription }
        }
    }

    private func save() {
        guard operation == nil, let device = validatedDevice() else { return }
        operation = .saving
        probeResult = nil
        Task {
            defer { operation = nil }
            do {
                if isNew { try await store.add(device) }
                else { try await store.update(device) }
                onFinish()
            } catch { operationError = error.localizedDescription }
        }
    }
}
