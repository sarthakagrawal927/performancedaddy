import Foundation

/// Bundled catalog v2. Role descriptions are paraphrases of Apple's macOS-shipped
/// /usr/share/man/man8/<name>.8 pages, reviewed 2026-09-19. This contains no
/// machine-specific observations. Catalog matching never authenticates code.
public enum ProcessCatalog {
    public struct Entry: Sendable {
        public let name: String
        public let role: String
        public let category: String
        public var source: String { "macOS \(name)(8) · catalog v2" }
    }
    public static let entries: [Entry] = [
        .init(name: "cfprefsd", role: "Provides the preferences service apps use to read and save settings.", category: "App settings"),
        .init(name: "distnoted", role: "Distributes notifications between processes.", category: "System communication"),
        .init(name: "coreaudiod", role: "Provides Core Audio services used by macOS audio features.", category: "Audio"),
        .init(name: "launchd", role: "Manages system and user services, including launching jobs when requested.", category: "Service manager"),
        .init(name: "WindowServer", role: "Manages windows, combines their visual content and routes input events.", category: "Display and input"),
        .init(name: "mds", role: "Provides file metadata services used by Spotlight and other clients.", category: "Search"),
        .init(name: "mdworker", role: "Scans and indexes file metadata for Spotlight when files or mounted volumes change.", category: "Search indexing"),
        .init(name: "trustd", role: "Evaluates certificate trust for other processes.", category: "Certificate trust"),
        .init(name: "secd", role: "Controls access to keychain items and changes to those items.", category: "Keychain"),
        .init(name: "amfid", role: "Checks the integrity of files that run on the system.", category: "Code integrity"),
        .init(name: "syspolicyd", role: "Evaluates system policy for software installation, loading and execution.", category: "Software policy"),
        .init(name: "notifyd", role: "Provides the macOS notification service used for communication between components.", category: "System communication"),
        .init(name: "nsurlsessiond", role: "Performs background URL-session tasks on behalf of apps.", category: "Background transfers"),
        .init(name: "mDNSResponder", role: "Resolves DNS names and discovers network services using Bonjour.", category: "Network discovery"),
        .init(name: "configd", role: "Maintains system configuration state and notifies apps when it changes.", category: "System configuration"),
        .init(name: "networkserviceproxy", role: "Manages proxy configuration and communication for Apple system services.", category: "System networking"),
        .init(name: "apsd", role: "Supports Apple Push Notification delivery.", category: "Push notifications"),
        .init(name: "cloudd", role: "Provides the system service behind CloudKit features.", category: "CloudKit"),
        .init(name: "bird", role: "Supports the Documents in the Cloud feature.", category: "Cloud documents"),
        .init(name: "photolibraryd", role: "Handles requests involving the photo library.", category: "Photo library"),
        .init(name: "photoanalysisd", role: "Analyzes photo libraries in the background for People, Memories and visual search.", category: "Photo analysis"),
        .init(name: "fileproviderd", role: "Coordinates file-provider extensions, file enumeration and property lookup.", category: "File providers"),
        .init(name: "sharedfilelistd", role: "Manages recent and favorite documents, apps and volumes, including Finder sidebar lists.", category: "Recent items"),
        .init(name: "sharingd", role: "Supports AirDrop, Handoff, Instant Hotspot and access to shared computers.", category: "Sharing and continuity"),
        .init(name: "rapportd", role: "Supports call handoff and communication features between Apple devices.", category: "Device continuity"),
        .init(name: "softwareupdated", role: "Runs macOS software-update work.", category: "Software updates"),
        .init(name: "installd", role: "Performs system package-installation work.", category: "Package installation"),
        .init(name: "lsd", role: "Provides services for the CoreServices frameworks. Apple's manual says not to terminate it.", category: "CoreServices"),
        .init(name: "pkd", role: "Manages and supervises PlugInKit plug-in services.", category: "App plug-ins"),
        .init(name: "runningboardd", role: "Manages process assertions that keep apps and services in the required operating state.", category: "Process lifecycle"),
        .init(name: "logd", role: "Collects and manages unified logging data from apps and system services.", category: "System logging"),
        .init(name: "diskarbitrationd", role: "Coordinates disk appearance, filesystem mounting and access by clients.", category: "Disks and mounting"),
        .init(name: "opendirectoryd", role: "Provides access to local and remote directory information, including users and groups.", category: "Users and directories"),
        .init(name: "backgroundtaskmanagementd", role: "Manages background and login items and their user-approval policy.", category: "Background items"),
        .init(name: "intelligenceplatformd", role: "Builds and serves an on-device knowledge graph for operating-system features.", category: "On-device intelligence"),
        .init(name: "intelligenceflowd", role: "Coordinates sessions, communication and state for intelligence services.", category: "Intelligence sessions"),
        .init(name: "modelmanagerd", role: "Manages machine-learning models and requests to run them.", category: "Machine-learning models"),
    ]
    private static let byName = Dictionary(uniqueKeysWithValues: entries.map { ($0.name, $0) })

    public static func match(executable: String) -> Entry? {
        let components = executable.split(separator: "/")
        guard !components.contains(".."), !components.contains("."),
              ["/System/Library/", "/usr/libexec/", "/usr/sbin/", "/sbin/"].contains(where: executable.hasPrefix),
              let name = components.last else { return nil }
        return byName[String(name)]
    }
}
