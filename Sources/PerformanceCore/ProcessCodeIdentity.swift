import Foundation
import NativeInspection
import Security

/// Evidence must reset across exec or credential changes, not only PID reuse.
public struct ProcessEvidenceKey: Hashable, Sendable {
    public let identity: ProcessIdentity
    public let uid: UInt32
    public let executable: String
    public init(_ process: LiveProcess) {
        identity = process.id; uid = process.uid; executable = process.executable
    }
}

/// Serial, explicit inspections. Cancelled queued requests do not start validation.
public actor ProcessCodeIdentityReader {
    public static let shared = ProcessCodeIdentityReader()
    public func inspect(_ process: LiveProcess) -> ProcessCodeIdentity {
        ProcessCodeIdentity.inspect(process)
    }
}

public struct ProcessCodeIdentity: Sendable {
    public enum Status: String, Sendable { case apple, developer, unattributed, unavailable }
    public let status: Status
    public let team: String?
    public let identifier: String?
    public let date: Date
    public let seconds: Double
    public var title: String {
        switch status {
        case .apple: "Apple code identity validated"
        case .developer: "Developer code identity validated"
        case .unattributed: "Code valid; publisher not established"
        case .unavailable: "Code identity could not be validated"
        }
    }

    static func result(valid: Bool, apple: Bool, developer: Bool, team: String?, identifier: String?, stable: Bool, seconds: Double = 0) -> Self {
        guard valid, stable else { return Self(status: .unavailable, team: nil, identifier: nil, date: Date(), seconds: seconds) }
        let knownTeam = team.flatMap { $0.isEmpty ? nil : $0 }
        return Self(status: apple ? .apple : developer && knownTeam != nil ? .developer : .unattributed,
                    team: developer || apple ? knownTeam : nil, identifier: identifier, date: Date(), seconds: seconds)
    }

    /// Explicit request only. PID/start/UID/path are checked on both sides of
    /// dynamic validation. Never validates a replacement on-disk executable as
    /// though it were the selected running process. Network access is disabled.
    public static func inspect(_ process: LiveProcess) -> Self {
        let began = ContinuousClock.now
        guard !Task.isCancelled else {
            return result(valid: false, apple: false, developer: false, team: nil, identifier: nil, stable: false)
        }
        func matches() -> Bool {
            var raw = PDProcess()
            guard pd_process(process.id.pid, &raw) == 1,
                  raw.started == process.id.started, raw.uid == process.uid else { return false }
            let path = withUnsafeBytes(of: &raw.path) { String(cString: $0.baseAddress!.assumingMemoryBound(to: CChar.self)) }
            return path == process.executable
        }
        var valid = false, apple = false, developer = false
        var team: String?, identifier: String?
        if matches(), !Task.isCancelled {
            var code: SecCode?
            let attributes = [kSecGuestAttributePid as String: NSNumber(value: process.id.pid)] as CFDictionary
            if SecCodeCopyGuestWithAttributes(nil, attributes, [], &code) == errSecSuccess, let code {
                let flags: SecCSFlags = .noNetworkAccess
                valid = SecCodeCheckValidity(code, flags, nil) == errSecSuccess
                func satisfies(_ expression: String) -> Bool {
                    var requirement: SecRequirement?
                    guard SecRequirementCreateWithString(expression as CFString, [], &requirement) == errSecSuccess,
                          let requirement else { return false }
                    return SecCodeCheckValidity(code, flags, requirement) == errSecSuccess
                }
                if valid {
                    apple = satisfies("anchor apple")
                    developer = apple || satisfies("anchor apple generic")
                    var staticCode: SecStaticCode?
                    var info: CFDictionary?
                    if SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess, let staticCode,
                       SecCodeCopySigningInformation(staticCode, SecCSFlags(rawValue: kSecCSSigningInformation), &info) == errSecSuccess {
                        let fields = info as? [String: Any]
                        team = fields?[kSecCodeInfoTeamIdentifier as String] as? String
                        identifier = fields?[kSecCodeInfoIdentifier as String] as? String
                    }
                }
            }
        }
        let stable = matches() && !Task.isCancelled
        let elapsed = began.duration(to: .now).components
        return result(valid: valid, apple: apple, developer: developer, team: team, identifier: identifier, stable: stable,
            seconds: Double(elapsed.seconds) + Double(elapsed.attoseconds) / 1e18)
    }
}
