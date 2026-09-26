import Foundation
@testable import PerformanceCore
import XCTest

final class AppAccessAuditTests: XCTestCase {
    func testStartupParserDoesNotExposeArgumentsOrEnvironment() {
        let item = AppAccessAuditReader.startupItem(
            ["Label": "com.example.helper", "ProgramArguments": ["/Applications/Example.app/Contents/MacOS/helper", "private-token"],
             "EnvironmentVariables": ["SECRET": "private-value"], "RunAtLoad": true, "KeepAlive": ["SuccessfulExit": false]],
            source: "/Library/LaunchAgents/com.example.helper.plist", context: "Login agent",
            liveExecutables: ["/Applications/Example.app/Contents/MacOS/helper"]
        )
        XCTAssertEqual(item.appPath, "/Applications/Example.app")
        XCTAssertTrue(item.observedRunning)
        XCTAssertTrue(item.launch.contains("Configured to run"))
        XCTAssertTrue(item.keepAlive.contains("Conditional"))
        XCTAssertFalse("\(item.label) \(item.executable ?? "") \(item.launch) \(item.keepAlive)".contains("private"))
    }

    func testDisabledAndNumericValuesDoNotBecomeApprovedStartup() {
        let disabled = AppAccessAuditReader.startupItem(
            ["RunAtLoad": true, "Disabled": true, "Program": "/opt/helper"],
            source: "/Library/LaunchDaemons/helper.plist", context: "Daemon", liveExecutables: [])
        XCTAssertTrue(disabled.launch.contains("Disabled in file"))
        let numeric = AppAccessAuditReader.startupItem(
            ["RunAtLoad": 1, "Program": "relative/helper"],
            source: "/Library/LaunchAgents/helper.plist", context: "Agent", liveExecutables: [])
        XCTAssertNil(numeric.executable)
        XCTAssertTrue(numeric.launch.contains("unknown"))
    }
}
