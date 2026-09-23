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
    public var name: String { URL(fileURLWithPath: path).lastPathComponent }
}

public struct ConfigurationScan: Sendable {
    public let files: [ConfigurationFile]
    public let sampledAt: Date
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
    public static func scan(home: String) -> ConfigurationScan {
        // URL standardization can rewrite /private/var to the /var symlink on
        // macOS. Preserve the caller's path so no-follow traversal stays exact.
        let home = home.hasSuffix("/") ? String(home.dropLast()) : home
        var files: [ConfigurationFile] = []
        var checked = 0
        for (relative, owner) in homeFiles {
            checked += 1
            let path = home + "/" + relative
            if let file = metadata(path: path, owner: owner) {
                files.append(file)
            }
        }
        return ConfigurationScan(files: files.sorted { $0.path < $1.path }, sampledAt: Date(),
            checkedPaths: checked)
    }

    private static func metadata(path: String, owner: String) -> ConfigurationFile? {
        let parts = path.split(separator: "/").map(String.init)
        guard let leaf = parts.last, !parts.contains("..") else { return nil }
        var fd = open("/", O_RDONLY | O_DIRECTORY | O_CLOEXEC)
        guard fd >= 0 else { return unavailable(path, owner) }
        defer { close(fd) }
        for component in parts.dropLast() {
            let next = openat(fd, component, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
            guard next >= 0 else {
                let code = errno
                if code == ENOENT { return nil }
                return unavailable(path, owner)
            }
            close(fd)
            fd = next
        }
        var info = stat()
        guard fstatat(fd, leaf, &info, AT_SYMLINK_NOFOLLOW) == 0 else {
            return errno == ENOENT ? nil : unavailable(path, owner)
        }
        let kind = info.st_mode & S_IFMT
        let regular = kind == S_IFREG
        return ConfigurationFile(path: path, owner: owner, scope: "User",
            status: regular ? "Present" : kind == S_IFLNK ? "Symlink · not followed" : "Not a regular file",
            bytes: regular ? UInt64(max(0, info.st_size)) : nil,
            modified: regular ? Date(timeIntervalSince1970: Double(info.st_mtimespec.tv_sec)) : nil)
    }

    private static func unavailable(_ path: String, _ owner: String) -> ConfigurationFile {
        ConfigurationFile(path: path, owner: owner, scope: "User",
            status: "Unavailable · access or path", bytes: nil, modified: nil)
    }
}
