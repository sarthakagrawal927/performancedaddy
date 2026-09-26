import Darwin
import Foundation

public struct StartupAuditItem: Identifiable, Sendable {
    public let id: String
    public let label: String
    public let executable: String?
    public let source: String
    public let context: String
    public let launch: String
    public let keepAlive: String
    public let observedRunning: Bool
    public let appPath: String?
}

public struct AppAccessAuditItem: Identifiable, Sendable {
    public var id: String { path }
    public let name: String
    public let path: String
    public let bundleID: String?
    /// Purpose strings disclose possible requests, not entitlements or grants.
    public let declaredRequests: [String]
    public let observedProcesses: Int
    public let startupItems: [StartupAuditItem]
    public var reviewCues: [String] {
        var result: [String] = []
        if !startupItems.isEmpty { result.append("Startup file") }
        if !declaredRequests.isEmpty {
            let first = declaredRequests.prefix(2).joined(separator: ", ")
            let more = declaredRequests.count > 2 ? " +\(declaredRequests.count - 2)" : ""
            result.append("May request: \(first)\(more)")
        }
        return result
    }
}

public struct AppAccessAudit: Sendable {
    public let date: Date
    public let apps: [AppAccessAuditItem]
    public let otherStartupItems: [StartupAuditItem]
    public let checkedApps: Int
    public let checkedStartupFiles: Int
    public let unavailable: Int
    public let limited: Bool
    public let liveSampleAvailable: Bool
}

/// An explicit, bounded scan of selected Info.plists and launch plists.
/// Parsed command arguments and environment values are discarded, never shown
/// or retained. No TCC database, helper, network request, or settings change.
public actor AppAccessAuditReader {
    private static let maxApps = 512
    private static let maxStartupFiles = 512
    private static let maxEntries = 2_048

    public init() {}

    public func scan(home: String, processes: [LiveProcess], liveSampleAvailable: Bool) -> AppAccessAudit {
        var unavailable = 0
        var limited = false
        var entriesSeen = 0
        var checkedStartupFiles = 0
        var startup: [StartupAuditItem] = []
        let startupRoots: [(String, String)] = [
            (home + "/Library/LaunchAgents", "User login agent"),
            ("/Library/LaunchAgents", "All-user login agent"),
            ("/Library/LaunchDaemons", "System startup daemon"),
        ]
        let liveExecutables = Set(processes.map(\.executable))

        for (root, context) in startupRoots {
            guard !Task.isCancelled else { limited = true; break }
            for path in Self.entries(in: root, unavailable: &unavailable) {
                entriesSeen += 1
                guard entriesSeen <= Self.maxEntries, checkedStartupFiles < Self.maxStartupFiles else {
                    limited = true; break
                }
                guard path.hasSuffix(".plist") else { continue }
                checkedStartupFiles += 1
                guard let data = ProcessMetadataReader.readRegularFile(path),
                      let dictionary = (try? PropertyListSerialization.propertyList(from: data, format: nil)) as? [String: Any]
                else { unavailable += 1; continue }
                let item = Self.startupItem(dictionary, source: path, context: context, liveExecutables: liveExecutables)
                startup.append(item)
            }
            if limited { break }
        }

        let runningApps = Dictionary(grouping: processes.compactMap { process -> String? in
            ProcessUnderstanding.appPath(for: process.executable)
        }, by: { $0 }).mapValues(\.count)
        let appRoots = ["/Applications", home + "/Applications"]
        var apps: [AppAccessAuditItem] = []
        var seenPaths = Set<String>()
        for root in appRoots {
            guard !Task.isCancelled else { limited = true; break }
            for path in Self.entries(in: root, unavailable: &unavailable) where path.hasSuffix(".app") {
                entriesSeen += 1
                guard entriesSeen <= Self.maxEntries, apps.count < Self.maxApps else {
                    limited = true; break
                }
                guard seenPaths.insert(path).inserted else { continue }
                guard let data = ProcessMetadataReader.readRegularFile(path + "/Contents/Info.plist"),
                      let info = (try? PropertyListSerialization.propertyList(from: data, format: nil)) as? [String: Any]
                else { unavailable += 1; continue }
                let name = (info["CFBundleDisplayName"] as? String)
                    ?? (info["CFBundleName"] as? String)
                    ?? URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent
                apps.append(AppAccessAuditItem(
                    name: name, path: path, bundleID: info["CFBundleIdentifier"] as? String,
                    declaredRequests: Self.declaredRequests(info),
                    observedProcesses: runningApps[path] ?? 0,
                    startupItems: startup.filter { $0.appPath == path }
                ))
            }
            if limited { break }
        }
        let appPaths = Set(apps.map(\.path))
        return AppAccessAudit(
            date: Date(), apps: apps.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending },
            otherStartupItems: startup.filter { $0.appPath == nil || !appPaths.contains($0.appPath!) }
                .sorted { $0.label.localizedStandardCompare($1.label) == .orderedAscending },
            checkedApps: apps.count, checkedStartupFiles: checkedStartupFiles,
            unavailable: unavailable, limited: limited, liveSampleAvailable: liveSampleAvailable
        )
    }

    private static func entries(in root: String, unavailable: inout Int) -> [String] {
        var metadata = stat()
        if lstat(root, &metadata) != 0 {
            if errno != ENOENT { unavailable += 1 }
            return []
        }
        guard metadata.st_mode & S_IFMT == S_IFDIR else { unavailable += 1; return [] }
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: root) else {
            unavailable += 1; return []
        }
        return names.sorted().map { root + "/" + $0 }
    }

    static func startupItem(_ dictionary: [String: Any], source: String, context: String,
                            liveExecutables: Set<String>) -> StartupAuditItem {
        let program = dictionary["Program"] as? String
            ?? (dictionary["ProgramArguments"] as? [String])?.first
        let executable = program.flatMap { $0.hasPrefix("/") && !$0.split(separator: "/").contains("..") ? $0 : nil }
        let appPath = executable.flatMap { ProcessUnderstanding.appPath(for: $0) }
        let label = (dictionary["Label"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = label?.isEmpty == false ? label! : URL(fileURLWithPath: source).deletingPathExtension().lastPathComponent
        let disabled = boolean(dictionary["Disabled"])
        let runAtLoad = boolean(dictionary["RunAtLoad"])
        let launch: String
        if disabled == true { launch = "Disabled in file; live overrides unknown" }
        else if runAtLoad == true { launch = "Configured to run when loaded" }
        else { launch = "Configured service; trigger or enabled state unknown" }
        let keepAlive = boolean(dictionary["KeepAlive"]) == true ? "Configured to stay running" :
            dictionary["KeepAlive"] is [String: Any] ? "Conditional keep-alive" : "No unconditional keep-alive found"
        return StartupAuditItem(id: source, label: name, executable: executable, source: source,
            context: context, launch: launch, keepAlive: keepAlive,
            observedRunning: executable.map { liveExecutables.contains($0) } ?? false,
            appPath: appPath)
    }

    private static func boolean(_ value: Any?) -> Bool? {
        guard let number = value as? NSNumber, CFGetTypeID(number) == CFBooleanGetTypeID() else { return nil }
        return number.boolValue
    }

    private static func declaredRequests(_ info: [String: Any]) -> [String] {
        let keys: [(String, String)] = [
            ("NSCameraUsageDescription", "Camera"),
            ("NSMicrophoneUsageDescription", "Microphone"),
            ("NSAppleEventsUsageDescription", "Automation"),
            ("NSLocationUsageDescription", "Location"),
            ("NSLocationWhenInUseUsageDescription", "Location"),
            ("NSContactsUsageDescription", "Contacts"),
            ("NSCalendarsUsageDescription", "Calendars"),
            ("NSRemindersUsageDescription", "Reminders"),
            ("NSPhotoLibraryUsageDescription", "Photos"),
        ]
        return Array(Set(keys.compactMap { key, name in
            (info[key] as? String)?.isEmpty == false ? name : nil
        })).sorted()
    }
}
