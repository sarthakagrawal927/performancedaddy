import Foundation

public actor DiagnosticHistoryStore {
    private struct Envelope: Codable {
        let version: Int
        let captures: [DiagnosticCapture]
    }

    private let fileURL: URL
    private let maximumBytes = 16 * 1_024 * 1_024

    public init(fileURL: URL = DiagnosticHistoryStore.defaultURL(filename: "diagnostic-history-v1.json")) {
        self.fileURL = fileURL
    }

    public func load() -> [DiagnosticCapture] {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: fileURL.path),
              let size = attributes[.size] as? NSNumber,
              size.intValue > 0, size.intValue <= maximumBytes,
              let data = try? Data(contentsOf: fileURL, options: [.mappedIfSafe]),
              let envelope = try? JSONDecoder().decode(Envelope.self, from: data),
              envelope.version == 1 else { return [] }
        return Self.validCaptures(envelope.captures)
    }

    public func save(_ captures: [DiagnosticCapture]) throws {
        let retained = Self.validCaptures(captures)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(Envelope(version: 1, captures: retained))
        guard data.count <= maximumBytes else { throw HistoryStoreError.tooLarge }
        try Self.write(data, to: fileURL)
    }

    private static func validCaptures(_ captures: [DiagnosticCapture]) -> [DiagnosticCapture] {
        Array(captures.filter { capture in
            let start = capture.startedAt.timeIntervalSince1970
            let end = capture.endedAt.timeIntervalSince1970
            return !capture.isFixture && start.isFinite && end.isFinite
                && end >= start && end - start <= 3_600 && capture.samples.count <= 2_000
        }.prefix(10))
    }

    public static func defaultURL(filename: String) -> URL {
        let root = (try? FileManager.default.url(for: .applicationSupportDirectory,
            in: .userDomainMask, appropriateFor: nil, create: true))
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
        return root.appendingPathComponent("PerformanceDaddy", isDirectory: true)
            .appendingPathComponent(filename, isDirectory: false)
    }

    fileprivate static func write(_ data: Data, to url: URL) throws {
        let directory = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700])
        try data.write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
}

public actor LifecycleHistoryStore {
    private struct Envelope: Codable {
        let version: Int
        let events: [ProcessLifecycleJournal.Event]
    }

    private let fileURL: URL
    private let maximumBytes = 2 * 1_024 * 1_024

    public init(fileURL: URL = DiagnosticHistoryStore.defaultURL(filename: "process-lifecycle-v1.json")) {
        self.fileURL = fileURL
    }

    public func load(at date: Date = Date()) -> [ProcessLifecycleJournal.Event] {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: fileURL.path),
              let size = attributes[.size] as? NSNumber,
              size.intValue > 0, size.intValue <= maximumBytes,
              let data = try? Data(contentsOf: fileURL, options: [.mappedIfSafe]),
              let envelope = try? JSONDecoder().decode(Envelope.self, from: data),
              envelope.version == 1 else { return [] }
        return ProcessLifecycleJournal.validPersistedEvents(envelope.events, at: date)
    }

    public func save(_ events: [ProcessLifecycleJournal.Event], at date: Date = Date()) throws {
        let retained = ProcessLifecycleJournal.validPersistedEvents(events, at: date)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(Envelope(version: 1, events: retained))
        guard data.count <= maximumBytes else { throw HistoryStoreError.tooLarge }
        try DiagnosticHistoryStore.write(data, to: fileURL)
    }
}

private enum HistoryStoreError: Error {
    case tooLarge
}
