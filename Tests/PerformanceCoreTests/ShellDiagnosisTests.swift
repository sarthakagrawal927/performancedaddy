import Foundation
import XCTest
@testable import PerformanceCore

final class ShellDiagnosisTests: XCTestCase {
    func testProfileParsingKeepsSelfSeparateAndRejectsPrivatePaths() {
        let text = """
        num calls time self name
         1) 2 120.00 60.00 75.00% 20.00 10.00 25.00% wrapper
         2) 1 100.00 100.00 25.00% 100.00 100.00 75.00% slow_function
         3) 1 nan 0 0% 0 0 0% bad
         4) 1 1 1 1% 1 1 1% /private/token
        -----------------------------------------------------------------------------------
         5) 1 5 5 5% 5 5 5% call_graph
        """
        let result = ShellProfileParser.parse(text)
        XCTAssertEqual(result.map(\.name), ["slow_function", "wrapper"])
        XCTAssertEqual(result.last?.totalMilliseconds, 120)
        XCTAssertEqual(result.last?.selfMilliseconds, 20)
    }

    func testConsentRequiredBeforeAnyConfiguredLaunch() async {
        do {
            _ = try await ShellDiagnoser().run(profileStartup: true, consent: false)
            XCTFail("Must reject missing consent")
        } catch ShellDiagnosisError.consentRequired {} catch { XCTFail("Unexpected error") }
    }

    func testSyntheticStartupProfilesFunctionWithoutChangingFixture() async throws {
        let directory = try fixture("function pd_test_delay() { /bin/sleep 0.06; }; pd_test_delay")
        defer { try? FileManager.default.removeItem(at: directory) }
        let before = try Data(contentsOf: directory.appendingPathComponent(".zshrc"))
        let report = try await ShellDiagnoser().measure(directory: directory, profileStartup: true)
        XCTAssertEqual(report.baseline.outcome, .completed)
        XCTAssertEqual(report.configured?.outcome, .completed)
        XCTAssertTrue(report.configured?.profileAvailable == true)
        XCTAssertTrue(report.configured?.functions.contains { $0.name == "pd_test_delay" && $0.selfMilliseconds >= 40 } == true)
        XCTAssertEqual(try Data(contentsOf: directory.appendingPathComponent(".zshrc")), before)
    }

    func testTimeoutIsBounded() async throws {
        let directory = try fixture("/bin/sleep 30")
        defer { try? FileManager.default.removeItem(at: directory) }
        let report = try await ShellDiagnoser().measure(directory: directory, profileStartup: true, timeout: 0.2)
        XCTAssertEqual(report.configured?.outcome, .timedOut)
        XCTAssertLessThan(report.configured!.elapsedMilliseconds, 1500)
    }

    func testLFOutputAndLogoutSuppression() async throws {
        let directory = try fixture("/bin/stty -onlcr; function pd_test_lf() { :; }; pd_test_lf")
        defer { try? FileManager.default.removeItem(at: directory) }
        try "/bin/sleep 30".write(to: directory.appendingPathComponent(".zlogout"), atomically: true, encoding: .utf8)
        let report = try await ShellDiagnoser().measure(directory: directory, profileStartup: true, timeout: 0.5)
        XCTAssertEqual(report.configured?.outcome, .completed)
        XCTAssertTrue(report.configured?.functions.contains { $0.name == "pd_test_lf" } == true)
    }

    func testCancellationDoesNotWaitForStartupSleep() async throws {
        let directory = try fixture("/bin/sleep 30")
        defer { try? FileManager.default.removeItem(at: directory) }
        let operation = Task { try await ShellDiagnoser().measure(directory: directory, profileStartup: true) }
        try await Task.sleep(for: .milliseconds(100))
        operation.cancel()
        let cancelledAt = ContinuousClock.now
        do { _ = try await operation.value; XCTFail("Cancellation must propagate") }
        catch is CancellationError {} catch { XCTFail("Unexpected error") }
        XCTAssertLessThan(cancelledAt.duration(to: .now), .seconds(1))
    }

    func testOutputLimitAndEarlyExit() async throws {
        let noisyLine = String(repeating: "x", count: 128)
        let directory = try fixture("repeat 3000; do print -r -- '\(noisyLine)'; done")
        defer { try? FileManager.default.removeItem(at: directory) }
        let noisy = try await ShellDiagnoser().measure(directory: directory, profileStartup: true, timeout: 20)
        XCTAssertEqual(noisy.configured?.outcome, .outputLimit)
        try "exit 7".write(to: directory.appendingPathComponent(".zshrc"), atomically: true, encoding: .utf8)
        let early = try await ShellDiagnoser().measure(directory: directory, profileStartup: true)
        XCTAssertEqual(early.configured?.outcome, .exitedEarly)
        XCTAssertEqual(early.configured?.exitCode, 7)
        XCTAssertFalse(early.configured!.profileAvailable)
    }

    private func fixture(_ script: String) throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("pd-shell-fixture-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        // Fixture files only; no owner shell configuration is executed or edited.
        try script.write(to: directory.appendingPathComponent(".zshrc"), atomically: true, encoding: .utf8)
        return directory
    }
}
