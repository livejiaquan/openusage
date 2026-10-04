import Foundation

struct RemoteUsageDevice: Codable, Hashable, Sendable, Identifiable {
    enum Platform: String, Codable, CaseIterable, Sendable {
        case linux = "Linux"
        case wsl = "Windows WSL"
        case windows = "Windows"
        case macOS = "Mac"

        func command(distribution: String?, linuxUser: String?) -> String {
            switch self {
            case .linux, .macOS: return "python3 -"
            case .wsl:
                var parts = ["wsl.exe"]
                if let distribution, !distribution.isEmpty { parts += ["--distribution", distribution] }
                if let linuxUser, !linuxUser.isEmpty { parts += ["--user", linuxUser] }
                return (parts + ["--exec", "python3", "-"]).joined(separator: " ")
            case .windows: return "py -3 -"
            }
        }
    }

    var id: String
    var name: String
    /// An SSH host alias from ~/.ssh/config, or a DNS name. Never interpolated into a shell command.
    var host: String
    var platform: Platform
    var enabled: Bool
    /// Optional so devices saved by older builds still decode.
    var sshUser: String?
    var sshPort: Int?
    var wslDistribution: String?
    var wslUser: String?

    init(id: String = "ssh-\(UUID().uuidString.lowercased())", name: String, host: String,
         platform: Platform, enabled: Bool = true, sshUser: String? = nil, sshPort: Int? = nil,
         wslDistribution: String? = nil, wslUser: String? = nil) {
        self.id = id
        self.name = name
        self.host = host
        self.platform = platform
        self.enabled = enabled
        self.sshUser = sshUser
        self.sshPort = sshPort
        self.wslDistribution = wslDistribution
        self.wslUser = wslUser
    }

    var isValid: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && host.range(of: #"^[A-Za-z0-9][A-Za-z0-9._-]{0,252}$"#, options: .regularExpression) != nil
            && (sshUser == nil || sshUser!.range(of: #"^[A-Za-z0-9_][A-Za-z0-9._@+\\-]{0,127}$"#, options: .regularExpression) != nil)
            && (sshPort == nil || (1...65_535).contains(sshPort!))
            && (wslDistribution == nil || wslDistribution!.range(of: #"^[A-Za-z0-9_][A-Za-z0-9._-]{0,63}$"#, options: .regularExpression) != nil)
            && (wslUser == nil || wslUser!.range(of: #"^[A-Za-z0-9_][A-Za-z0-9._-]{0,63}$"#, options: .regularExpression) != nil)
    }

    var connectionKey: String {
        [host, sshUser ?? "", sshPort.map(String.init) ?? "", platform.rawValue,
         wslDistribution ?? "", wslUser ?? ""].joined(separator: "|")
    }

    var command: String { platform.command(distribution: wslDistribution, linuxUser: wslUser) }
}
