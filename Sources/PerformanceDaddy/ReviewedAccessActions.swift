import AppKit
import Darwin
import Foundation
import PerformanceCore

struct LaunchFileTrashCandidate: Identifiable {
    let item: StartupAuditItem
    let device: dev_t
    let inode: ino_t
    let size: off_t
    let modifiedSeconds: time_t
    let modifiedNanoseconds: Int
    var id: String { item.source }

    init(item: StartupAuditItem, home: String) throws {
        let root = home + "/Library/LaunchAgents"
        let url = URL(fileURLWithPath: item.source)
        guard url.deletingLastPathComponent().path == root,
              item.source == root + "/" + url.lastPathComponent,
              url.pathExtension == "plist" else { throw ReviewedAccessActionError.unsupportedFile }
        var parent = stat()
        guard lstat(root, &parent) == 0, parent.st_mode & S_IFMT == S_IFDIR else {
            throw ReviewedAccessActionError.fileChanged
        }
        let identity = try Self.identity(at: item.source)
        self.item = item
        device = identity.st_dev
        inode = identity.st_ino
        size = identity.st_size
        modifiedSeconds = identity.st_mtimespec.tv_sec
        modifiedNanoseconds = identity.st_mtimespec.tv_nsec
    }

    @discardableResult
    func moveToTrash() async throws -> URL {
        let current = try Self.identity(at: item.source)
        guard current.st_dev == device, current.st_ino == inode,
              current.st_size == size, current.st_mtimespec.tv_sec == modifiedSeconds,
              current.st_mtimespec.tv_nsec == modifiedNanoseconds else {
            throw ReviewedAccessActionError.fileChanged
        }
        let url = URL(fileURLWithPath: item.source)
        let moved = try await NSWorkspace.shared.recycle([url])
        guard let destination = moved[url] else { throw ReviewedAccessActionError.trashFailed }
        return destination
    }

    private static func identity(at path: String) throws -> stat {
        var metadata = stat()
        guard lstat(path, &metadata) == 0,
              metadata.st_mode & S_IFMT == S_IFREG,
              metadata.st_uid == geteuid() else { throw ReviewedAccessActionError.fileChanged }
        return metadata
    }
}

struct PermissionResetCandidate: Identifiable {
    let appPath: String
    let appName: String
    let bundleID: String
    let area: String
    let service: String
    var id: String { appPath + "|" + area }

    init?(app: AppAccessAuditItem, area: String) {
        guard let bundleID = app.bundleID,
              let service = PermissionDecisionResetter.service(for: area),
              bundleID.count <= 255, bundleID.contains("."),
              bundleID.unicodeScalars.allSatisfy({ CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789.-").contains($0) })
        else { return nil }
        appPath = app.path
        appName = app.name
        self.bundleID = bundleID
        self.area = area
        self.service = service
    }
}

actor PermissionDecisionResetter {
    private static let services = [
        "Full Disk Access": "SystemPolicyAllFiles", "Accessibility": "Accessibility",
        "Input Monitoring": "ListenEvent", "Screen Recording": "ScreenCapture",
        "Camera": "Camera", "Microphone": "Microphone", "Automation": "AppleEvents",
        "Contacts": "AddressBook", "Photos": "Photos", "Calendars": "Calendar",
        "Reminders": "Reminders", "Bluetooth": "BluetoothAlways"
    ]

    static func service(for area: String) -> String? { services[area] }

    func reset(_ target: PermissionResetCandidate) throws {
        guard Self.services[target.area] == target.service else {
            throw ReviewedAccessActionError.unsupportedPermission
        }
        guard Self.currentBundleID(at: target.appPath) == target.bundleID else {
            throw ReviewedAccessActionError.appChanged
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/tccutil")
        process.arguments = ["reset", target.service, target.bundleID]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw ReviewedAccessActionError.resetFailed
        }
    }

    private static func currentBundleID(at appPath: String) -> String? {
        let infoPath = appPath + "/Contents/Info.plist"
        var metadata = stat()
        guard lstat(infoPath, &metadata) == 0,
              metadata.st_mode & S_IFMT == S_IFREG,
              metadata.st_size > 0, metadata.st_size <= 1_048_576,
              let data = try? Data(contentsOf: URL(fileURLWithPath: infoPath)),
              let info = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        else { return nil }
        return info["CFBundleIdentifier"] as? String
    }
}

enum ReviewedAccessActionError: LocalizedError {
    case unsupportedFile, fileChanged, trashFailed, unsupportedPermission, appChanged, resetFailed

    var errorDescription: String? {
        switch self {
        case .unsupportedFile: "Only a single file in your own LaunchAgents folder can be moved to Trash here."
        case .fileChanged: "The launch file changed or is no longer an owned regular file. Refresh and review it again."
        case .trashFailed: "Finder did not move the launch file to Trash."
        case .unsupportedPermission: "This permission category cannot be reset here. Use System Settings."
        case .appChanged: "The app bundle changed since the audit. Refresh and review it again."
        case .resetFailed: "macOS did not reset this app's permission decision. Check the exact entry in System Settings."
        }
    }
}
