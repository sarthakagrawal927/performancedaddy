import Foundation
@testable import PerformanceCore
import XCTest

final class ConfigurationInventoryTests: XCTestCase {
    func testAllowlistFindsConfigMetadataWithoutScanningSecretsOrRecursing() throws {
        let root = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let project = root.appendingPathComponent("project")
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
        try Data("private settings".utf8).write(to: root.appendingPathComponent(".zshrc"))
        try Data("private credentials".utf8).write(to: root.appendingPathComponent(".env"))
        try Data("{}".utf8).write(to: project.appendingPathComponent("package.json"))
        try FileManager.default.createDirectory(at: root.appendingPathComponent(".codex"), withIntermediateDirectories: true)
        try Data("do not parse this content".utf8).write(to: root.appendingPathComponent(".codex/config.toml"))
        let result = ConfigurationInventory.scan(home: root.path, processes: [process(project.path)])
        XCTAssertEqual(Set(result.files.map(\.name)), [".zshrc", "package.json", "config.toml"])
        XCTAssertEqual(result.files.first { $0.name == "package.json" }?.nearbyProcesses, 1)
        XCTAssertEqual(result.files.first { $0.name == ".zshrc" }?.bytes, 16)
        XCTAssertEqual(result.projectDirectories, 1)
    }

    func testFileAndDirectorySymlinksAreNotFollowed() throws {
        let root = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createSymbolicLink(atPath: root.appendingPathComponent(".zshrc").path,
            withDestinationPath: "/nonexistent/private-target")
        try FileManager.default.createSymbolicLink(atPath: root.appendingPathComponent(".codex").path,
            withDestinationPath: "/nonexistent/private-directory")
        let result = ConfigurationInventory.scan(home: root.path, processes: [])
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
        let result = ConfigurationInventory.scan(home: root.path, processes: [])
        XCTAssertEqual(result.files.count, 2)
        XCTAssertTrue(result.files.allSatisfy { $0.bytes == nil && $0.modified == nil })
    }

    func testDirectoriesAreBoundedAndSensitiveRootsExcluded() throws {
        let root = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let processes = (0..<40).map { process(root.path + "/project-\($0)", pid: Int32($0 + 10)) }
            + [process(root.path + "/.ssh"), process(root.path + "/.kube"), process("/tmp/outside"),
               process(root.path + "/Library/Containers/example"), process(root.path + "/project/node_modules/tool")]
        let result = ConfigurationInventory.scan(home: root.path, processes: processes)
        XCTAssertEqual(result.projectDirectories, 32)
        XCTAssertEqual(result.omittedDirectories, 8)
        XCTAssertEqual(result.checkedPaths, 12 + 32 * 13)
        XCTAssertTrue(result.files.isEmpty)
    }

    private func fixture() throws -> URL {
        let root = URL(fileURLWithPath: "/private/tmp", isDirectory: true)
            .appendingPathComponent("performancedaddy-config-test-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }
    private func process(_ directory: String, pid: Int32 = 100) -> LiveProcess {
        .init(id: .init(pid: pid, started: 1), parent: 1, uid: getuid(), name: "node",
            executable: "/opt/bin/node", directory: directory, cpu: 0, memory: 0)
    }
}
