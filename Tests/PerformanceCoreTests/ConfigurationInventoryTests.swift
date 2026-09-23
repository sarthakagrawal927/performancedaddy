import Foundation
@testable import PerformanceCore
import XCTest

final class ConfigurationInventoryTests: XCTestCase {
    func testHomeAllowlistFindsConfigMetadataWithoutScanningProjectsOrSecrets() throws {
        let root = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let project = root.appendingPathComponent("project")
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
        try Data("private settings".utf8).write(to: root.appendingPathComponent(".zshrc"))
        try Data("private credentials".utf8).write(to: root.appendingPathComponent(".env"))
        try Data("{}".utf8).write(to: project.appendingPathComponent("package.json"))
        try FileManager.default.createDirectory(at: root.appendingPathComponent(".codex"), withIntermediateDirectories: true)
        try Data("do not parse this content".utf8).write(to: root.appendingPathComponent(".codex/config.toml"))
        let result = ConfigurationInventory.scan(home: root.path)
        XCTAssertEqual(Set(result.files.map(\.name)), [".zshrc", "config.toml"])
        XCTAssertEqual(result.files.first { $0.name == ".zshrc" }?.bytes, 16)
        XCTAssertEqual(result.checkedPaths, 12)
    }

    func testFileAndDirectorySymlinksAreNotFollowed() throws {
        let root = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createSymbolicLink(atPath: root.appendingPathComponent(".zshrc").path,
            withDestinationPath: "/nonexistent/private-target")
        try FileManager.default.createSymbolicLink(atPath: root.appendingPathComponent(".codex").path,
            withDestinationPath: "/nonexistent/private-directory")
        let result = ConfigurationInventory.scan(home: root.path)
        XCTAssertEqual(result.files.first { $0.name == ".zshrc" }?.status, "Symlink · not followed")
        XCTAssertNil(result.files.first { $0.name == ".zshrc" }?.bytes)
        XCTAssertEqual(result.files.first { $0.owner == "Codex" }?.status, "Unavailable · access or path")
    }

    func testExistingLinkedTargetsRemainUninspected() throws {
        let root = try fixture()
        let outside = try fixture()
        defer { try? FileManager.default.removeItem(at: root); try? FileManager.default.removeItem(at: outside) }
        try Data(repeating: 7, count: 1234).write(to: outside.appendingPathComponent("config.toml"))
        try FileManager.default.createSymbolicLink(atPath: root.appendingPathComponent(".zshrc").path,
            withDestinationPath: outside.appendingPathComponent("config.toml").path)
        try FileManager.default.createSymbolicLink(atPath: root.appendingPathComponent(".codex").path,
            withDestinationPath: outside.path)
        let result = ConfigurationInventory.scan(home: root.path)
        XCTAssertEqual(result.files.count, 2)
        XCTAssertTrue(result.files.allSatisfy { $0.bytes == nil && $0.modified == nil })
    }

    private func fixture() throws -> URL {
        let root = URL(fileURLWithPath: "/private/tmp", isDirectory: true)
            .appendingPathComponent("performancedaddy-config-test-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }
}
