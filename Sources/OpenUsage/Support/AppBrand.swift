import Foundation

/// This fork's user-facing identity. OpenUsage's trademark policy (TRADEMARK.md) requires a fork to
/// use its own name and logo and to say it isn't the official app, so every name, folder, and link a
/// user can see reads from here. Internal module and type names keep the upstream spelling so merges
/// from upstream stay small.
enum AppBrand {
    static let name = "Tokamak"
    /// Folder under ~/Library/Application Support and ~/Library/Logs. Distinct from OpenUsage's so the
    /// two apps can be installed side by side without sharing caches, locks, or logs.
    static let supportFolder = "Tokamak"
    static let cliCommand = "tokamak"
    static let repositoryURL = "https://github.com/livejiaquan/openusage"
    static let newIssueURL = "https://github.com/livejiaquan/openusage/issues/new/choose"
    static let upstreamURL = "https://github.com/robinebers/openusage"
}
