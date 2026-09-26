import Foundation

public enum AppAccessReviewStatus: String, Codable, CaseIterable, Sendable {
    case shownAllowed
    case shownOff
    case notListed
}

public struct AppAccessReviewNote: Codable, Equatable, Sendable {
    public let appPath: String
    public let bundleID: String?
    public let area: String
    public let status: AppAccessReviewStatus
    public let checkedAt: Date
}

/// Local notes about what the owner saw in System Settings. These are never
/// presented as live permission grants or service-management state.
public actor AppAccessReviewStore {
    private struct Envelope: Codable {
        let version: Int
        let notes: [AppAccessReviewNote]
    }

    public static let privacyAreas = [
        "Full Disk Access", "Accessibility", "Input Monitoring", "Screen Recording",
        "Camera", "Microphone", "Automation", "Location", "Contacts",
        "Photos", "Calendars", "Reminders", "Files and Folders", "Bluetooth"
    ]
    public static let loginItemsArea = "Login Items"
    private static let allowedAreas = Set(privacyAreas + [loginItemsArea])
    private let fileURL: URL
    private let maximumBytes = 512 * 1_024
    private var cached: [AppAccessReviewNote]?

    public init(fileURL: URL = DiagnosticHistoryStore.defaultURL(filename: "app-access-review-v1.json")) {
        self.fileURL = fileURL
    }

    public func load() -> [AppAccessReviewNote] {
        if let cached { return cached }
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: fileURL.path),
              let size = attributes[.size] as? NSNumber,
              size.intValue > 0, size.intValue <= maximumBytes,
              let data = try? Data(contentsOf: fileURL),
              let envelope = try? JSONDecoder().decode(Envelope.self, from: data),
              envelope.version == 1 else { cached = []; return [] }
        let notes = Self.valid(envelope.notes)
        cached = notes
        return notes
    }

    @discardableResult
    public func record(appPath: String, bundleID: String?, area: String,
                       status: AppAccessReviewStatus, at date: Date = Date()) throws -> [AppAccessReviewNote] {
        guard Self.allowedAreas.contains(area), appPath.hasPrefix("/"),
              appPath.hasSuffix(".app"), !appPath.contains("/../"),
              date.timeIntervalSince1970.isFinite else { throw StoreError.invalidNote }
        var notes = load().filter { !($0.appPath == appPath && $0.area == area) }
        notes.append(AppAccessReviewNote(appPath: appPath, bundleID: bundleID,
                                         area: area, status: status, checkedAt: date))
        try save(notes)
        return notes
    }

    @discardableResult
    public func remove(appPath: String, area: String) throws -> [AppAccessReviewNote] {
        let notes = load().filter { !($0.appPath == appPath && $0.area == area) }
        try save(notes)
        return notes
    }

    private func save(_ notes: [AppAccessReviewNote]) throws {
        let retained = Self.valid(notes)
        guard retained.count <= 2_048 else { throw StoreError.tooLarge }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(Envelope(version: 1, notes: retained))
        guard data.count <= maximumBytes else { throw StoreError.tooLarge }
        try DiagnosticHistoryStore.write(data, to: fileURL)
        cached = retained
    }

    private static func valid(_ notes: [AppAccessReviewNote]) -> [AppAccessReviewNote] {
        var seen = Set<String>()
        return Array(notes.reversed().filter { note in
            let key = note.appPath + "\u{0}" + note.area
            return allowedAreas.contains(note.area) && note.appPath.hasPrefix("/")
                && note.appPath.hasSuffix(".app") && !note.appPath.contains("/../")
                && note.checkedAt.timeIntervalSince1970.isFinite && seen.insert(key).inserted
        }.reversed())
    }

    private enum StoreError: Error { case invalidNote, tooLarge }
}
