import Foundation

/// Optional, read-only session archives. These extend local history without changing where the
/// Claude and Codex CLIs write their live sessions.
struct AdditionalLogRoots: Equatable, Sendable {
    var claudeProjectDirectories: [String] = []
    var codexSessionDirectories: [String] = []

    static func load(text: String?) -> Self {
        guard let text,
              let data = text.data(using: .utf8),
              let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let sources = root["logSources"] as? [String: Any]
        else { return Self() }

        func paths(_ key: String) -> [String] {
            guard let values = sources[key] as? [String] else { return [] }
            var seen: Set<String> = []
            return values.compactMap { value in
                let path = NSString(string: value).expandingTildeInPath
                guard path.hasPrefix("/"), seen.insert(path).inserted else { return nil }
                return path
            }
        }
        return Self(
            claudeProjectDirectories: paths("claudeProjectDirectories"),
            codexSessionDirectories: paths("codexSessionDirectories")
        )
    }

    static func read() -> Self {
        let path = NSString(string: "~/.openusage/config.json").expandingTildeInPath
        return load(text: try? String(contentsOfFile: path, encoding: .utf8))
    }
}
