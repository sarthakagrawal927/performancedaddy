import Foundation
import Security

public struct InstalledAppCodeEvidence: Sendable {
    public enum Status: Sendable { case valid, unavailable }
    public let status: Status
    public let team: String?
    public let identifier: String?
    public let sandboxed: Bool?
    public let declaredCapabilities: [String]
    public let checkedAt: Date

    /// Static declarations are capabilities, not macOS privacy approvals.
    public static func inspect(path: String) -> Self {
        let unknown = Self(status: .unavailable, team: nil, identifier: nil, sandboxed: nil,
                           declaredCapabilities: [], checkedAt: Date())
        guard path.hasPrefix("/"), !path.split(separator: "/").contains(".."),
              path.hasSuffix(".app") else { return unknown }
        var code: SecStaticCode?
        guard SecStaticCodeCreateWithPath(URL(fileURLWithPath: path, isDirectory: true) as CFURL,
                                          [], &code) == errSecSuccess, let code,
              SecStaticCodeCheckValidity(code, .noNetworkAccess, nil) == errSecSuccess
        else { return unknown }
        var info: CFDictionary?
        guard SecCodeCopySigningInformation(code, SecCSFlags(rawValue: kSecCSSigningInformation), &info) == errSecSuccess,
              let fields = info as? [String: Any] else { return unknown }
        let entitlements = fields[kSecCodeInfoEntitlementsDict as String] as? [String: Any] ?? [:]
        let capabilities: [(String, String)] = [
            ("com.apple.security.device.camera", "Camera entitlement"),
            ("com.apple.security.device.audio-input", "Microphone entitlement"),
            ("com.apple.security.personal-information.location", "Location entitlement"),
            ("com.apple.security.personal-information.addressbook", "Contacts entitlement"),
            ("com.apple.security.automation.apple-events", "Automation entitlement"),
            ("com.apple.security.network.client", "Outbound network entitlement"),
            ("com.apple.security.network.server", "Incoming network entitlement"),
        ].compactMap { key, label in
            (entitlements[key] as? Bool) == true ? (key, label) : nil
        }
        return Self(status: .valid,
                    team: fields[kSecCodeInfoTeamIdentifier as String] as? String,
                    identifier: fields[kSecCodeInfoIdentifier as String] as? String,
                    sandboxed: entitlements["com.apple.security.app-sandbox"] as? Bool,
                    declaredCapabilities: capabilities.map(\.1).sorted(), checkedAt: Date())
    }
}

public actor InstalledAppCodeEvidenceReader {
    public init() {}
    public func inspect(path: String) -> InstalledAppCodeEvidence {
        InstalledAppCodeEvidence.inspect(path: path)
    }
}
