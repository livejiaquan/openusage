import XCTest
@testable import OpenUsage

final class RemoteUsageDeviceDraftTests: XCTestCase {
    func testInvalidFieldsAreIdentifiedBeforeSSHIsAttempted() {
        var draft = RemoteUsageDeviceDraft()
        draft.host = "lab;whoami"
        draft.sshUser = "bad;user"
        draft.sshPort = "70000"
        XCTAssertEqual(Set(draft.validationErrors.keys), [.name, .host, .sshUser, .sshPort])
        XCTAssertThrowsError(try draft.makeDevice())
    }

    func testPortMustBeAnIntegerWithinTheSSHRange() {
        for port in ["0", "-1", "65536", "abc", "22.5"] {
            var draft = validDraft()
            draft.sshPort = port
            XCTAssertNotNil(draft.validationErrors[.sshPort], port)
            XCTAssertThrowsError(try draft.makeDevice(), port)
        }
        for port in ["", "1", "22", "65535"] {
            var draft = validDraft()
            draft.sshPort = port
            XCTAssertNil(draft.validationErrors[.sshPort], port)
            XCTAssertNoThrow(try draft.makeDevice(), port)
        }
    }

    func testSavingTrimsFieldsAndUsesDefaultsForEmptyOptionalValues() throws {
        var draft = validDraft()
        draft.name = "  Lab  "
        draft.host = "  lab  "
        draft.sshUser = "  "
        draft.sshPort = "  "
        let device = try draft.makeDevice()
        XCTAssertEqual(device.name, "Lab")
        XCTAssertEqual(device.host, "lab")
        XCTAssertNil(device.sshUser)
        XCTAssertNil(device.sshPort)
        XCTAssertTrue(device.isValid)
    }

    func testEditingPreservesIdentityAndDisabledState() throws {
        let original = RemoteUsageDevice(id: "ssh-existing", name: "Office", host: "office",
                                        platform: .wsl, enabled: false, sshUser: "DOMAIN\\person",
                                        sshPort: 2222, wslDistribution: "Ubuntu", wslUser: "linuxuser")
        var draft = RemoteUsageDeviceDraft(device: original)
        draft.name = "Renamed"
        let saved = try draft.makeDevice()
        XCTAssertEqual(saved.id, "ssh-existing")
        XCTAssertFalse(saved.enabled)
        XCTAssertEqual(saved.sshUser, "DOMAIN\\person")
        XCTAssertEqual(saved.sshPort, 2222)
        XCTAssertEqual(saved.wslDistribution, "Ubuntu")
        XCTAssertEqual(saved.wslUser, "linuxuser")
    }

    func testNewDevicesStartOnLinux() {
        XCTAssertEqual(RemoteUsageDeviceDraft().platform, .linux)
    }

    func testHiddenWSLFieldsCannotBlockOrLeakIntoOtherSystems() throws {
        var draft = validDraft(platform: .wsl)
        draft.wslUser = "invalid user"
        draft.wslDistribution = "Ubuntu;whoami"
        XCTAssertNotNil(draft.validationErrors[.wslUser])
        XCTAssertNotNil(draft.validationErrors[.wslDistribution])
        draft.platform = .linux
        XCTAssertTrue(draft.validationErrors.isEmpty)
        let saved = try draft.makeDevice()
        XCTAssertNil(saved.wslUser)
        XCTAssertNil(saved.wslDistribution)
    }

    func testProbeIdentityChangesForConnectionEditsButNotADeviceRename() {
        var draft = validDraft(platform: .wsl)
        let tested = draft.connectionIdentity
        draft.name = "New display name"
        XCTAssertEqual(draft.connectionIdentity, tested)
        draft.host = "other-host"
        XCTAssertNotEqual(draft.connectionIdentity, tested)
        draft = validDraft(platform: .wsl)
        draft.wslUser = "another-user"
        XCTAssertNotEqual(draft.connectionIdentity, tested)
    }

    private func validDraft(platform: RemoteUsageDevice.Platform = .linux) -> RemoteUsageDeviceDraft {
        var draft = RemoteUsageDeviceDraft()
        draft.name = "Lab"
        draft.host = "lab"
        draft.platform = platform
        return draft
    }
}
