import AppKit
import Foundation
@testable import PerformanceCore
@testable import PerformanceDaddy
import XCTest

@MainActor
final class ReviewedAccessActionsTests: XCTestCase {
    func testOwnedLaunchFileMovesToTrash() async throws {
        let home = fixtureHome()
        let file = home.appendingPathComponent("Library/LaunchAgents/com.example.fixture.plist")
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("fixture".utf8).write(to: file)
        defer { try? FileManager.default.removeItem(at: home) }

        let candidate = try LaunchFileTrashCandidate(item: startupItem(path: file.path), home: home.path)
        let trashed = try await candidate.moveToTrash()
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: trashed.path))
        try FileManager.default.removeItem(at: trashed)
    }

    func testChangedLaunchFileIsNotMoved() async throws {
        let home = fixtureHome()
        let file = home.appendingPathComponent("Library/LaunchAgents/com.example.fixture.plist")
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("fixture".utf8).write(to: file)
        defer { try? FileManager.default.removeItem(at: home) }

        let candidate = try LaunchFileTrashCandidate(item: startupItem(path: file.path), home: home.path)
        try Data("changed fixture".utf8).write(to: file)
        do {
            _ = try await candidate.moveToTrash()
            XCTFail("Expected a changed file to be rejected")
        } catch ReviewedAccessActionError.fileChanged {
            XCTAssertTrue(FileManager.default.fileExists(atPath: file.path))
        }
    }

    func testPermissionResetUsesExactAppIdentity() async throws {
        let home = fixtureHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let app = home.appendingPathComponent("Fixture.app")
        let plist = app.appendingPathComponent("Contents/Info.plist")
        try FileManager.default.createDirectory(at: plist.deletingLastPathComponent(), withIntermediateDirectories: true)
        let bundleID = "com.example.performancedaddyfixture.\(UUID().uuidString)"
        try writeInfo(bundleID: bundleID, to: plist)
        let item = AppAccessAuditItem(name: "Fixture", path: app.path, bundleID: bundleID,
                                      declaredRequests: [], observedProcesses: 0, startupItems: [])
        let candidate = try XCTUnwrap(PermissionResetCandidate(app: item, area: "Camera"))
        XCTAssertEqual(candidate.service, "Camera")
        XCTAssertNil(PermissionResetCandidate(app: item, area: "Login Items"))

        try writeInfo(bundleID: "com.example.changed", to: plist)
        do {
            try await PermissionDecisionResetter().reset(candidate)
            XCTFail("Expected a changed bundle ID to be rejected")
        } catch ReviewedAccessActionError.appChanged {}

        try writeInfo(bundleID: bundleID, to: plist)
        do {
            try await PermissionDecisionResetter().reset(candidate)
            XCTFail("Expected macOS to reject an unregistered fixture app")
        } catch ReviewedAccessActionError.resetFailed {}
    }

    private func fixtureHome() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("performancedaddy-actions-\(UUID().uuidString)", isDirectory: true)
    }

    private func startupItem(path: String) -> StartupAuditItem {
        StartupAuditItem(id: path, label: "Fixture", executable: nil, source: path,
                         context: "User login agent", launch: "Configured service",
                         keepAlive: "No unconditional keep-alive found", observedRunning: false, appPath: nil)
    }

    private func writeInfo(bundleID: String, to url: URL) throws {
        let plist = ["CFBundleIdentifier": bundleID, "CFBundleName": "Fixture"]
        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        try data.write(to: url, options: .atomic)
    }
}
