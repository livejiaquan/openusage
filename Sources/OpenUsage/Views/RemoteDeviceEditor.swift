import SwiftUI

struct RemoteDeviceEditor: View {
    let store: RemoteUsageDeviceStore
    let onFinish: () -> Void
    private let isNew: Bool
    @State private var draft: RemoteUsageDeviceDraft
    @State private var showSSHOptions: Bool
    @State private var showWSLOptions: Bool
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
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(isNew ? "Add Device" : "Edit Device").font(.body.weight(.semibold))
                Spacer()
                Button("Cancel", action: onFinish).buttonStyle(.borderless).disabled(operation != nil)
            }
            field(.name, "Device Name", placeholder: "Lab Computer", text: $draft.name)
            Divider()
            groupTitle("Connection", systemImage: "network")
            field(.host, "Host or IP Address", placeholder: "lab-server or 192.168.1.20", text: $draft.host)
            field(.sshUser, windowsSSH ? "Windows Username" : "SSH Username",
                  placeholder: "From SSH config", text: $draft.sshUser, optional: true)
            if windowsSSH { help("The Windows account used to log in over SSH.") }
            DisclosureGroup("Advanced SSH", isExpanded: $showSSHOptions) {
                field(.sshPort, "Port", placeholder: "From SSH config, otherwise 22", text: $draft.sshPort, optional: true)
                    .padding(.top, 8)
            }
            .font(.caption.weight(.medium))
            Divider()
            groupTitle("History Location", systemImage: "folder")
            HStack {
                Text("Read Logs From").font(.caption)
                Spacer(minLength: 8)
                Picker("Read Logs From", selection: $draft.platform) {
                    ForEach(RemoteUsageDevice.Platform.allCases, id: \.self) { platform in
                        Text(platform == .wsl ? "Windows + WSL" : platform.rawValue).tag(platform)
                    }
                }
                .labelsHidden().pickerStyle(.menu).disabled(operation != nil)
            }
            if draft.platform == .wsl {
                help("SSH connects to Windows; history is read inside WSL.")
                DisclosureGroup("WSL Environment", isExpanded: $showWSLOptions) {
                    VStack(alignment: .leading, spacing: 10) {
                        field(.wslDistribution, "Distribution", placeholder: "Windows default", text: $draft.wslDistribution, optional: true)
                        field(.wslUser, "Linux Username", placeholder: "Distribution default", text: $draft.wslUser, optional: true)
                        help("The Linux account whose Claude and Codex logs you want to import.")
                    }
                    .padding(.top, 8)
                }
                .font(.caption.weight(.medium))
            } else {
                help(draft.platform == .windows ? "Reads this Windows account's logs using Python 3."
                     : "Reads this SSH account's Claude and Codex logs.")
            }
            Divider()
            feedback
            actions
            help("Uses your SSH keys. Only daily usage summaries are saved on this Mac.")
        }
        .padding(12).cardSurface()
        .onChange(of: draft.connectionIdentity) { probeResult = nil; operationError = nil }
        .onChange(of: focusedField) { old, _ in if let old { touchedFields.insert(old) } }
        .task { focusedField = .name }
    }

    private var windowsSSH: Bool { draft.platform == .wsl || draft.platform == .windows }

    private func groupTitle(_ title: String, systemImage: String) -> some View {
        Label(title, systemImage: systemImage).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
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
                Text(operation == .testing ? "Checking SSH and Python…" : "Saving and Importing History…").font(.caption)
            }
            .accessibilityElement(children: .combine)
        } else if let probeResult {
            VStack(alignment: .leading, spacing: 4) {
                Label("SSH and Python Ready", systemImage: "checkmark.circle.fill")
                    .font(.caption.weight(.medium)).foregroundStyle(Theme.positive)
                help(probeResult)
                help("History will be checked when you save.")
            }
        } else if let operationError {
            Label(operationError, systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(Theme.notice)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var actions: some View {
        HStack(spacing: 8) {
            Button("Check SSH") { testConnection() }.buttonStyle(.bordered)
            Spacer(minLength: 0)
            Button(isNew ? "Add Device" : "Save Changes") { save() }.buttonStyle(.borderedProminent)
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
