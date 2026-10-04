import Foundation

struct RemoteUsageDevice: Codable, Hashable, Sendable, Identifiable {
    enum Platform: String, Codable, CaseIterable, Sendable {
        case linux = "Linux"
        case wsl = "Windows WSL"
        case windows = "Windows"
        case macOS = "Mac"

        var command: String {
            switch self {
            case .linux, .macOS: "python3 -"
            case .wsl: "wsl.exe -e python3 -"
            case .windows: "py -3 -"
            }
        }
    }

    var id: String
    var name: String
    /// An SSH host alias from ~/.ssh/config, or a DNS name. Never interpolated into a shell command.
    var host: String
    var platform: Platform
    var enabled: Bool

    init(id: String = "ssh-\(UUID().uuidString.lowercased())", name: String, host: String,
         platform: Platform, enabled: Bool = true) {
        self.id = id
        self.name = name
        self.host = host
        self.platform = platform
        self.enabled = enabled
    }

    var isValid: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && host.range(of: #"^[A-Za-z0-9][A-Za-z0-9._-]{0,252}$"#, options: .regularExpression) != nil
    }
}
