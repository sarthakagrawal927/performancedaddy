import Foundation
import NativeInspection

public struct ShellFunctionTiming: Sendable, Equatable, Identifiable {
    public var id: String { name }
    public let name: String
    public let calls: Int
    public let totalMilliseconds: Double
    public let selfMilliseconds: Double
}

public struct ShellTrial: Sendable {
    public enum Outcome: String, Sendable { case completed, timedOut, outputLimit, exitedEarly }
    public let outcome: Outcome
    public let elapsedMilliseconds: Double
    public let exitCode: Int?
    public let functions: [ShellFunctionTiming]
    public let profileAvailable: Bool
}

public struct ShellDiagnosisReport: Sendable {
    public let baseline: ShellTrial
    public let configured: ShellTrial?
}

/// Parse only the first zprof table. Discard call graphs, command output and paths.
public enum ShellProfileParser {
    public static func parse(_ text: String) -> [ShellFunctionTiming] {
        var rows: [ShellFunctionTiming] = []
        var seen = Set<String>()
        var separators = 0
        for line in text.split(whereSeparator: \.isNewline) {
            if line.hasPrefix("---") {
                separators += 1
                if separators > 1 || !rows.isEmpty { break }
                continue
            }
            let fields = line.split(whereSeparator: \.isWhitespace)
            guard fields.count == 9, fields[0].hasSuffix(")"),
                  Int(fields[0].dropLast()) != nil,
                  let calls = Int(fields[1]), calls > 0,
                  let total = Double(fields[2]), total.isFinite, total >= 0,
                  let own = Double(fields[5]), own.isFinite, own >= 0,
                  own <= total + 0.02 else { continue }
            let name = String(fields[8])
            guard name.utf8.count <= 100, !name.isEmpty,
                  name.utf8.allSatisfy({ (65...90).contains($0) || (97...122).contains($0) ||
                      (48...57).contains($0) || [45, 46, 95, 58].contains($0) }),
                  seen.insert(name).inserted else { continue }
            rows.append(.init(name: name, calls: calls, totalMilliseconds: total, selfMilliseconds: own))
            if rows.count == 100 { break }
        }
        return rows.sorted { $0.selfMilliseconds > $1.selfMilliseconds }
    }
}

public enum ShellDiagnosisError: Error { case consentRequired, launchFailed, invalidDirectory }

/// Explicit experiment, not part of the read-only background sampler.
public actor ShellDiagnoser {
    public init() {}

    public func run(profileStartup: Bool, consent: Bool) async throws -> ShellDiagnosisReport {
        guard !profileStartup || consent else { throw ShellDiagnosisError.consentRequired }
        let directory = FileManager.default.homeDirectoryForCurrentUser
        return try await measure(directory: directory, profileStartup: profileStartup)
    }

    // Internal fixture entry point deliberately excluded from the product UI.
    func measure(directory: URL, profileStartup: Bool, timeout: Double = 10) async throws -> ShellDiagnosisReport {
        guard directory.isFileURL, directory.path.hasPrefix("/") else { throw ShellDiagnosisError.invalidDirectory }
        let baseline = try await trial(directory: directory, profile: false, timeout: timeout)
        try Task.checkCancellation()
        let configured = profileStartup ? try await trial(directory: directory, profile: true, timeout: timeout) : nil
        return ShellDiagnosisReport(baseline: baseline, configured: configured)
    }

    private func trial(directory: URL, profile: Bool, timeout: Double) async throws -> ShellTrial {
        try Task.checkCancellation()
        let manager = FileManager.default
        let temporary = manager.temporaryDirectory.appendingPathComponent("PerformanceDaddy-shell-\(UUID().uuidString)")
        try manager.createDirectory(at: temporary, withIntermediateDirectories: false,
                                    attributes: [.posixPermissions: 0o700])
        defer { try? manager.removeItem(at: temporary) }
        let marker = "PD_" + UUID().uuidString.replacingOccurrences(of: "-", with: "")
        // No interpolation of user-controlled paths into executable shell code.
        let bootstrap = """
        zmodload zsh/zprof
        ZDOTDIR=$PD_SOURCE_DIRECTORY
        unset PD_SOURCE_DIRECTORY
        if [[ -r "$ZDOTDIR/.zshenv" ]]; then source "$ZDOTDIR/.zshenv"; fi
        """
        if profile {
            try bootstrap.write(to: temporary.appendingPathComponent(".zshenv"), atomically: true, encoding: .utf8)
        }
        let command = "builtin print -r -- '\(marker)_READY'; " +
            (profile ? "builtin zprof; " : "") + "builtin print -r -- '\(marker)_END'; builtin unset HISTFILE; builtin unsetopt RCS; builtin exit"
        let arguments = ["/bin/zsh", profile ? "-lic" : "-flic", command]
        // Deliberately do not inherit arbitrary credentials or terminal integration hooks.
        let environment = [
            "PATH=/usr/bin:/bin:/usr/sbin:/sbin", "TERM=xterm-256color", "LANG=C", "LC_ALL=C",
            "ZDOTDIR=\(temporary.path)", "PD_SOURCE_DIRECTORY=\(directory.path)",
        ]
        let argv = arguments.map { strdup($0) } + [nil]
        let envp = environment.map { strdup($0) } + [nil]
        defer { argv.forEach { free($0) }; envp.forEach { free($0) } }
        let start = ContinuousClock.now
        let probe = argv.withUnsafeBufferPointer { a in
            envp.withUnsafeBufferPointer { e in pd_shell_start(a.baseAddress, e.baseAddress, directory.path) }
        }
        guard let probe else { throw ShellDiagnosisError.launchFailed }
        defer { pd_shell_close(probe) }
        var output = Data()
        var buffer = [UInt8](repeating: 0, count: 8192)
        var readyMilliseconds: Double?
        var code: Int32 = 0
        var outcome = ShellTrial.Outcome.exitedEarly
        while true {
            try Task.checkCancellation()
            let count = pd_shell_read(probe, &buffer, buffer.count)
            if count > 0 { output.append(contentsOf: buffer.prefix(Int(count))) }
            let elapsed = Self.milliseconds(start.duration(to: .now))
            if readyMilliseconds == nil,
               String(decoding: output, as: UTF8.self).replacingOccurrences(of: "\r\n", with: "\n")
                .contains("\(marker)_READY\n") { readyMilliseconds = elapsed }
            if output.count > 262_144 { outcome = .outputLimit; break }
            if elapsed >= max(0.05, min(timeout, 30)) * 1000 { outcome = .timedOut; break }
            if pd_shell_status(probe, &code) != 0 {
                // Drain only currently available bytes; never wait on inherited descriptors.
                while true {
                    let remaining = pd_shell_read(probe, &buffer, buffer.count)
                    if remaining <= 0 { break }
                    output.append(contentsOf: buffer.prefix(Int(remaining)))
                    if output.count > 262_144 { break }
                }
                outcome = output.count > 262_144 ? .outputLimit : .exitedEarly
                break
            }
            try await Task.sleep(for: .milliseconds(5))
        }
        let text = String(decoding: output, as: UTF8.self).replacingOccurrences(of: "\r\n", with: "\n")
        let begin = text.range(of: "\(marker)_READY\n")
        let end = text.range(of: "\(marker)_END\n")
        if outcome == .exitedEarly, code == 0, let begin, let end, begin.upperBound <= end.lowerBound {
            outcome = .completed
        }
        let profileText: String
        if let begin, let end, begin.upperBound <= end.lowerBound { profileText = String(text[begin.upperBound..<end.lowerBound]) }
        else { profileText = "" }
        return ShellTrial(outcome: outcome,
                          elapsedMilliseconds: readyMilliseconds ?? Self.milliseconds(start.duration(to: .now)),
                          exitCode: outcome == .timedOut || outcome == .outputLimit ? nil : Int(code),
                          functions: profile && outcome == .completed ? ShellProfileParser.parse(profileText) : [],
                          profileAvailable: profile && outcome == .completed && profileText.contains("self") && profileText.contains("name"))
    }

    private static func milliseconds(_ duration: Duration) -> Double {
        let parts = duration.components
        return Double(parts.seconds) * 1000 + Double(parts.attoseconds) / 1e15
    }
}
