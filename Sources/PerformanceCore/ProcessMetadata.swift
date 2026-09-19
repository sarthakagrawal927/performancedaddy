import Darwin
import Foundation

public struct StartupPolicy: Sendable {
    public let source: String
    public let context: String
    public let launch: String
    public let keepAlive: String

    public static func parse(_ dictionary: [String: Any], executable: String, source: String, context: String, bundle: String? = nil) -> StartupPolicy? {
        let program = dictionary["Program"] as? String ?? (dictionary["ProgramArguments"] as? [String])?.first
        let bundleProgram = (dictionary["BundleProgram"] as? String).flatMap { relative -> String? in
            guard let bundle, !relative.hasPrefix("/"), !relative.split(separator: "/").contains("..") else { return nil }
            return bundle + "/" + relative
        }
        guard !executable.isEmpty, (program ?? bundleProgram) == executable else { return nil }
        func boolean(_ value: Any?) -> Bool? {
            guard let number = value as? NSNumber, CFGetTypeID(number) == CFBooleanGetTypeID() else { return nil }
            return number.boolValue
        }
        let run = boolean(dictionary["RunAtLoad"])
        let keep = boolean(dictionary["KeepAlive"])
        return StartupPolicy(source: source, context: context,
            launch: run == true ? "Configured to run when loaded (not proof of boot or login launch)." : "No verified run-at-load policy; demand, schedule or other triggers may apply.",
            keepAlive: keep == true ? "Configured to keep running." :
                dictionary["KeepAlive"] is [String: Any] ? "Conditional keep-alive policy; conditions are not evaluated." :
                "No unconditional keep-alive policy found.")
    }
}

public struct ProcessMetadata: Sendable {
    public let date: Date
    public let policies: [StartupPolicy]
    public let checked: Int
    public let skipped: Int
    public let limited: Bool
    public let seconds: Double
}

/// Explicit inspector request only. No argv/environment collection, file writes,
/// service changes or network requests. No cached cross-process trust decisions.
public actor ProcessMetadataReader {
    public init() {}
    public func inspect(_ process: LiveProcess) -> ProcessMetadata {
        let started = ContinuousClock.now
        var roots = [
            (FileManager.default.homeDirectoryForCurrentUser.path + "/Library/LaunchAgents", "User login-session agent", Optional<String>.none),
            ("/Library/LaunchAgents", "Login-session agent", nil),
            ("/Library/LaunchDaemons", "System daemon", nil),
            ("/System/Library/LaunchAgents", "macOS login-session agent", nil),
            ("/System/Library/LaunchDaemons", "macOS system daemon", nil),
        ]
        if let bundle = ProcessUnderstanding.appPath(for: process.executable) {
            roots.insert((bundle + "/Contents/Library/LaunchDaemons", "App-bundled daemon", bundle), at: 0)
            roots.insert((bundle + "/Contents/Library/LaunchAgents", "App-bundled agent", bundle), at: 0)
        }
        var policies: [StartupPolicy] = []
        var checked = 0, skipped = 0
        var limited = false
        var entries = 0
        scan: for (root, context, bundle) in roots {
            guard let iterator = FileManager.default.enumerator(at: URL(fileURLWithPath: root), includingPropertiesForKeys: [], options: [.skipsSubdirectoryDescendants, .skipsPackageDescendants], errorHandler: { _, _ in skipped += 1; return false }) else { skipped += 1; continue }
            while let url = iterator.nextObject() as? URL {
                entries += 1
                guard !Task.isCancelled, checked < 512, entries <= 2048 else { limited = true; break scan }
                guard url.pathExtension == "plist" else { continue }
                checked += 1
                let path = url.path
                guard let data = Self.readRegularFile(path),
                      let dictionary = (try? PropertyListSerialization.propertyList(from: data, format: nil)) as? [String: Any] else {
                    skipped += 1; continue
                }
                if let policy = StartupPolicy.parse(dictionary, executable: process.executable, source: path, context: context, bundle: bundle) {
                    policies.append(policy)
                }
            }
        }
        let elapsed = started.duration(to: .now).components
        return ProcessMetadata(date: Date(), policies: policies, checked: checked, skipped: skipped,
            limited: limited, seconds: Double(elapsed.seconds) + Double(elapsed.attoseconds) / 1e18)
    }

    /// Descriptor traversal refuses symlinks at every component and caps reads.
    static func readRegularFile(_ path: String) -> Data? {
        guard path.hasPrefix("/") else { return nil }
        let parts = path.split(separator: "/").map(String.init)
        guard !parts.isEmpty, !parts.contains("..") else { return nil }
        var fd = open("/", O_RDONLY | O_DIRECTORY | O_CLOEXEC)
        guard fd >= 0 else { return nil }
        defer { close(fd) }
        for (index, part) in parts.enumerated() {
            let flags = O_RDONLY | O_NOFOLLOW | O_CLOEXEC | O_NONBLOCK | (index == parts.count - 1 ? 0 : O_DIRECTORY)
            let next = openat(fd, part, flags)
            guard next >= 0 else { return nil }
            close(fd); fd = next
        }
        var status = stat()
        guard fstat(fd, &status) == 0, status.st_mode & S_IFMT == S_IFREG,
              status.st_size > 0, status.st_size <= 131_072 else { return nil }
        var data = Data(count: Int(status.st_size))
        let count = data.withUnsafeMutableBytes { read(fd, $0.baseAddress, $0.count) }
        guard count == data.count else { return nil }
        return data
    }
}
