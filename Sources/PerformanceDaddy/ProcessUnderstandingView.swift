import SwiftUI
import PerformanceCore
import ServiceManagement

struct ProcessUnderstandingView: View {
    let process: LiveProcess
    var ancestor: LiveProcess? = nil
    @State private var metadata: ProcessMetadata?
    @State private var inspecting = false
    @State private var identity: ProcessCodeIdentity?
    @State private var validating = false
    @State private var validationRequest: UUID?
    private let reader = ProcessMetadataReader()
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let entry = process.catalog {
                Text(entry.category).fontWeight(.medium)
                Text(entry.role)
                Text("\(entry.source). Name and system-location match; validate code identity separately.")
                    .font(.caption).foregroundStyle(PerformanceTheme.secondaryInk)
            } else {
                Text(ProcessUnderstanding.explanation(for: process))
                Text("Source: executable path and name · not verified ownership")
                    .font(.caption).foregroundStyle(PerformanceTheme.secondaryInk)
            }
            if process.appPath == nil, let ancestor, let path = ancestor.appPath {
                Text("Observed ancestor app: \(URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent)")
                Text("PID \(ancestor.id.pid) · ancestry suggests launch context, not verified ownership or a restart policy.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Text("Code identity").font(.subheadline.weight(.semibold)).accessibilityAddTraits(.isHeader)
            if let identity {
                Text(identity.title).fontWeight(.medium)
                if let team = identity.team { Text("Team: \(team)").textSelection(.enabled) }
                if let identifier = identity.identifier { Text(identifier).font(.caption).textSelection(.enabled) }
                Text(identity.status == .unavailable ? "Unavailable evidence does not establish that the code is invalid." : "Valid code is not proof of safety or necessity.")
                    .font(.caption).foregroundStyle(.secondary)
                DisclosureGroup("Validation details") {
                    Text("Checked \(identity.date.formatted(date: .omitted, time: .standard)) · \(Int(identity.seconds * 1000)) ms. Local running-code check; no online revocation or notarization check. App association remains path-based.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            Button(validating ? "Validating…" : "Validate running code") {
                validating = true
                validationRequest = UUID()
            }.disabled(validating)
            Text("Startup").font(.subheadline.weight(.semibold)).accessibilityAddTraits(.isHeader)
            if let metadata {
                Text(metadata.policies.isEmpty
                     ? "Observed running now · no exact startup policy match"
                     : "Configured and observed running now")
                    .fontWeight(.medium)
                DisclosureGroup("Configured policies · \(metadata.policies.count) matches") {
                  ForEach(Array(metadata.policies.enumerated()), id: \.offset) { _, policy in
                    VStack(alignment: .leading, spacing: 5) {
                        Text(policy.context).fontWeight(.medium)
                        Text(policy.launch)
                        Text(policy.keepAlive)
                        Text(policy.source).font(.caption).textSelection(.enabled)
                    }
                  }
                }
                if metadata.policies.isEmpty {
                    Text("No exact executable match found in the checked launch configurations. This does not mean automatic startup is disabled.")
                }
                Text("Checked \(metadata.checked) files · \(metadata.skipped) unavailable files or directories\(metadata.limited ? " · scan limit reached" : "") · \(Int(metadata.seconds * 1000)) ms")
                    .font(.caption).foregroundStyle(.secondary)
                DisclosureGroup("Coverage and limitations") {
                  Text("Checked \(metadata.date.formatted(date: .omitted, time: .standard)). The selected identity was present in the latest PerformanceDaddy sample. Registration, approval, wrappers and live launchd overrides are not inspected. Configured-and-observed does not prove the policy launched this process or that a later matching process is an automatic restart. Limited to 512 files and 2,048 directory entries; symlinks and files over 128 KiB are skipped.")
                    .font(.caption).foregroundStyle(.secondary)
                }
            }
            Button(inspecting ? "Inspecting…" : metadata == nil ? "Inspect startup metadata" : "Recheck metadata") {
                inspecting = true
                Task {
                    metadata = await reader.inspect(process)
                    inspecting = false
                }
            }.disabled(inspecting)
            Button("Review Login Items in Settings") { SMAppService.openSystemSettingsLoginItems() }
                .help("Opens macOS settings; does not change startup items")
        }.font(.callout).frame(maxWidth: .infinity, alignment: .leading).padding(8)
        .task(id: validationRequest) {
            guard validationRequest != nil else { return }
            let result = await ProcessCodeIdentityReader.shared.inspect(process)
            guard !Task.isCancelled else { return }
            identity = result
            validating = false
        }
    }
}

struct ProcessStopHistoryView: View {
    @ObservedObject var model: LiveViewModel
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Stop history").font(.title2.bold()).accessibilityAddTraits(.isHeader)
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.cancelAction)
            }
            Text("Only stops requested through PerformanceDaddy. Up to 500 events from the last 24 hours are stored locally; active exit watches are not resumed after relaunch. Sampling gaps can hide activity. A matching executable is not proof of a restart.")
                .font(.caption).foregroundStyle(PerformanceTheme.secondaryInk)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 16) {
                    if model.lifecycle.events.isEmpty { Text("No retained stop events from the last 24 hours.") }
                    ForEach(model.lifecycle.events.reversed()) { event in
                        VStack(alignment: .leading, spacing: 4) {
                            Text("\(URL(fileURLWithPath: event.executable).lastPathComponent) · \(event.date.formatted(date: .omitted, time: .standard))").fontWeight(.medium)
                            Text(event.text).font(.callout)
                            Text(event.executable).font(.caption).textSelection(.enabled)
                                .foregroundStyle(PerformanceTheme.secondaryInk)
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        }.padding(20).frame(width: 440, height: 480).background(PerformanceTheme.fog)
    }
}
