import Darwin
import Foundation

public struct ConfigurationFile: Identifiable, Sendable {
    public var id: String { path }
    public let path: String
    public let owner: String
    public let scope: String
    public let status: String
    public let bytes: UInt64?
    public let modified: Date?
    public let nearbyProcesses: Int
    public var name: String { URL(fileURLWithPath: path).lastPathComponent }
}

public struct ConfigurationScan: Sendable {
    public let files: [ConfigurationFile]
    public let sampledAt: Date
    public let projectDirectories: Int
    public let omittedDirectories: Int
    public let checkedPaths: Int
}

/// Metadata-only inventory. No parser, file-content read, environment read,
/// recursive walk or link resolution. Descriptor-relative traversal prevents
/// symlinked directories from redirecting the inventory to other locations.
public enum ConfigurationInventory {
    private static let homeFiles: [(String, String)] = [
        (".zshrc", "Zsh"), (".zprofile", "Zsh"), (".zshenv", "Zsh"),
        (".bashrc", "Bash"), (".bash_profile", "Bash"), (".profile", "Shell"),
        (".config/fish/config.fish", "Fish"), (".gitconfig", "Git"),
        (".codex/config.toml", "Codex"), (".claude/settings.json", "Claude"),
        (".config/opencode/opencode.json", "OpenCode"),
        (".config/opencode/opencode.jsonc", "OpenCode"),
    ]
    private static let projectFiles: [(String, String)] = [
        ("package.json", "Node tooling"), ("tsconfig.json", "TypeScript"),
        ("pyproject.toml", "Python tooling"), ("uv.toml", "uv"),
        ("Cargo.toml", "Rust"), ("rust-toolchain.toml", "Rust"),
        ("Package.swift", "Swift"), (".tool-versions", "Tool versions"),
        (".nvmrc", "Node version"), (".node-version", "Node version"),
        (".python-version", "Python version"),
        (".codex/config.toml", "Codex"), (".claude/settings.json", "Claude"),
    ]
    private static let excludedComponents: Set<String> = [
        ".ssh", ".aws", ".azure", ".kube", ".gnupg", "gcloud", "Keychains",
        "Library", ".Trash", ".cache", "node_modules", ".git",
    ]
    /// Personal top-level folders are not project roots; their direct children
    /// still count, so ~/Desktop/project remains an observed directory.
    private static let nonProjectRoots: Set<String> = [
        "Desktop", "Downloads", "Documents", "Movies", "Music", "Pictures", "Public",
    ]

    public static func scan(home: String, processes: [LiveProcess]) -> ConfigurationScan {
        // URL standardization can rewrite /private/var to the /var symlink on
        // macOS. Preserve the caller's path so no-follow traversal stays exact.
        let home = home.hasSuffix("/") ? String(home.dropLast()) : home
        var eligible: [(String, LiveProcess)] = []
        for process in processes {
            guard process.isUserProcess, process.stopRestriction == nil,
                  process.directory.hasPrefix(home + "/") else { continue }
            var directory = process.directory
            while directory.hasSuffix("/") { directory = String(directory.dropLast()) }
            guard directory != home else { continue }
            let relative = directory.dropFirst(home.count + 1)
            guard relative.contains("/") || !nonProjectRoots.contains(String(relative)) else { continue }
            let components = NSString(string: directory).pathComponents
            guard !components.contains(where: { excludedComponents.contains($0) || $0 == ".." }) else { continue }
            eligible.append((directory, process))
        }
        let grouped = Dictionary(grouping: eligible, by: \.0)
        let directories = grouped.keys.sorted()
        let chosen = Array(directories.prefix(32))
        var files: [ConfigurationFile] = []
        var checked = 0
        func inspect(_ root: String, _ candidates: [(String, String)], scope: String, nearby: Int) {
            for (relative, owner) in candidates {
                checked += 1
                let path = root + "/" + relative
                if let file = metadata(path: path, owner: owner, scope: scope, nearby: nearby) {
                    files.append(file)
                }
            }
        }
        inspect(home, homeFiles, scope: "User", nearby: 0)
        for directory in chosen {
            inspect(directory, projectFiles, scope: "Observed directory", nearby: grouped[directory]?.count ?? 0)
        }
        return ConfigurationScan(files: files.sorted { $0.path < $1.path }, sampledAt: Date(),
            projectDirectories: chosen.count, omittedDirectories: max(0, directories.count - chosen.count), checkedPaths: checked)
    }

    private static func metadata(path: String, owner: String, scope: String, nearby: Int) -> ConfigurationFile? {
        let parts = path.split(separator: "/").map(String.init)
        guard let leaf = parts.last, !parts.contains("..") else { return nil }
        var fd = open("/", O_RDONLY | O_DIRECTORY | O_CLOEXEC)
        guard fd >= 0 else { return unavailable(path, owner, scope, nearby) }
        defer { close(fd) }
        for component in parts.dropLast() {
            let next = openat(fd, component, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
            guard next >= 0 else {
                let code = errno
                if code == ENOENT { return nil }
                return unavailable(path, owner, scope, nearby)
            }
            close(fd)
            fd = next
        }
        var info = stat()
        guard fstatat(fd, leaf, &info, AT_SYMLINK_NOFOLLOW) == 0 else {
            return errno == ENOENT ? nil : unavailable(path, owner, scope, nearby)
        }
        let kind = info.st_mode & S_IFMT
        let regular = kind == S_IFREG
        return ConfigurationFile(path: path, owner: owner, scope: scope,
            status: regular ? "Present" : kind == S_IFLNK ? "Symlink · not followed" : "Not a regular file",
            bytes: regular ? UInt64(max(0, info.st_size)) : nil,
            modified: regular ? Date(timeIntervalSince1970: Double(info.st_mtimespec.tv_sec)) : nil,
            nearbyProcesses: nearby)
    }

    private static func unavailable(_ path: String, _ owner: String, _ scope: String, _ nearby: Int) -> ConfigurationFile {
        ConfigurationFile(path: path, owner: owner, scope: scope,
            status: "Unavailable · access or path", bytes: nil, modified: nil, nearbyProcesses: nearby)
    }
}
