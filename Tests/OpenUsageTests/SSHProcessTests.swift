import XCTest
@testable import OpenUsage

/// Uses /bin/sh in place of ssh: the runner only cares about pipes, exit status, and timing.
final class SSHProcessTests: XCTestCase {
    private func run(_ script: String, input: Data = Data(), timeout: TimeInterval = 10,
                     maxOutput: Int = 1_000_000) async throws -> SSHProcess.Output {
        try await SSHProcess.run(executable: "/bin/sh", arguments: ["-c", script], input: input,
                                 timeout: timeout, maxOutput: maxOutput)
    }

    func testFeedsStdinAndReturnsStdout() async throws {
        let output = try await run("cat", input: Data("exporter".utf8))
        XCTAssertEqual(output.status, 0)
        XCTAssertEqual(String(decoding: output.stdout, as: UTF8.self), "exporter")
    }

    func testHungRemoteCommandTimesOut() async {
        let started = Date()
        do {
            _ = try await run("sleep 30", timeout: 1)
            XCTFail("Expected a timeout")
        } catch {
            XCTAssertEqual(error as? SSHProcess.Failure, .timedOut)
        }
        XCTAssertLessThan(Date().timeIntervalSince(started), 10)
    }

    func testLargeStderrDoesNotDeadlockStdout() async throws {
        // 300 KB of stderr fills the OS pipe buffer long before stdout finishes.
        let output = try await run("head -c 300000 /dev/zero | tr '\\0' x >&2; echo done")
        XCTAssertEqual(output.status, 0)
        XCTAssertEqual(String(decoding: output.stdout, as: UTF8.self), "done\n")
        XCTAssertEqual(output.stderr.count, SSHProcess.stderrLimit)
    }

    func testCommandThatIgnoresStdinDoesNotRaiseSIGPIPE() async throws {
        // Before the fix, writing the script to an exited ssh killed the whole app with SIGPIPE.
        let output = try await run("exit 3", input: Data(count: 4 * 1024 * 1024))
        XCTAssertEqual(output.status, 3)
    }

    func testOversizedOutputStopsEarly() async {
        do {
            _ = try await run("head -c 5000000 /dev/zero", maxOutput: 1_000_000)
            XCTFail("Expected an oversized failure")
        } catch {
            XCTAssertEqual(error as? SSHProcess.Failure, .oversized)
        }
    }

    func testBackgroundChildHoldingStderrDoesNotBlockResult() async throws {
        // Like a ControlPersist master: a detached child keeps stderr open after the command exits.
        let started = Date()
        let output = try await run("(sleep 30 >/dev/null &); echo ready")
        XCTAssertEqual(String(decoding: output.stdout, as: UTF8.self), "ready\n")
        XCTAssertLessThan(Date().timeIntervalSince(started), 15)
    }
}
