import XCTest
@testable import OpenUsage

final class AdditionalLogRootsTests: XCTestCase {
    func testParsesArchivesAlongsideExistingProxyConfiguration() {
        let config = AdditionalLogRoots.load(text: #"""
        {
          "proxy": {"enabled": true, "url": "socks5://localhost:1080"},
          "logSources": {
            "claudeProjectDirectories": ["/tmp/claude-projects", "/tmp/claude-projects"],
            "codexSessionDirectories": ["/tmp/codex-sessions", "relative/path"]
          }
        }
        """#)

        XCTAssertEqual(config.claudeProjectDirectories, ["/tmp/claude-projects"])
        XCTAssertEqual(config.codexSessionDirectories, ["/tmp/codex-sessions"])
    }

    func testMissingOrMalformedConfigHasNoExtraRoots() {
        XCTAssertEqual(AdditionalLogRoots.load(text: nil), AdditionalLogRoots())
        XCTAssertEqual(AdditionalLogRoots.load(text: "not json"), AdditionalLogRoots())
        XCTAssertEqual(AdditionalLogRoots.load(text: #"{"proxy":{"enabled":true}}"#), AdditionalLogRoots())
    }
}
