import SwiftUI
import ServiceManagement

@main
struct PerformanceDaddyApp: App {
    @NSApplicationDelegateAdaptor(PerformanceDaddyDelegate.self) private var delegate
    @StateObject private var live = LiveViewModel()
    @StateObject private var diagnosis = DiagnosisViewModel()
    @StateObject private var updates = AppUpdates()
    var body: some Scene {
        Window("PerformanceDaddy", id: "main") {
            DashboardView(model: diagnosis, live: live)
                .frame(minWidth: 980, minHeight: 800)
                .task { updates.start(live: live, diagnosis: diagnosis) }
                .onAppear {
                    delegate.activeWork = {
                        if diagnosis.isRecording { return "A diagnosis recording is still running." }
                        if live.performingAction { return "A reviewed action is still running." }
                        return nil
                    }
                }
        }
        .defaultSize(width: 1_180, height: 800)
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandGroup(after: .appInfo) {
                Button("Check for Updates…") { updates.check() }
                    .disabled(!updates.canCheck || !updates.isIdle)
                Toggle("Automatically Check for Updates", isOn: $updates.automaticallyChecks)
            }
        }
        MenuBarExtra {
            LiveMenu(model: live, diagnosis: diagnosis, updates: updates)
        } label: {
            Label(live.usedMemory, systemImage: "memorychip")
        }
    }
}

@MainActor
final class PerformanceDaddyDelegate: NSObject, NSApplicationDelegate {
    var activeWork: (() -> String?)?
    func applicationDidFinishLaunching(_ notification: Notification) {
        if let icon = PerformanceAppIcon.image { NSApplication.shared.applicationIconImage = icon }
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        DaddyQuitReview.shouldQuit(appName: "PerformanceDaddy", activeWork: activeWork?()) ? .terminateNow : .terminateCancel
    }
}

@MainActor
enum PerformanceAppIcon {
    static let image = DaddyResources.url(forResource: "PerformanceDaddy").flatMap(NSImage.init(contentsOf:))
}

private struct LiveMenu: View {
    @ObservedObject var model: LiveViewModel
    @ObservedObject var diagnosis: DiagnosisViewModel
    @ObservedObject var updates: AppUpdates
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var notifyEnabled = DaddyCompletionNotices.isEnabled
    @State private var notificationError = false
    @State private var loginError: String?
    var body: some View {
        DaddyMenuStatus(message: diagnosis.isRecording ? "Recording diagnosis" : model.performingAction ? "Action in progress" : model.paused ? "Monitoring paused" : "Monitoring while app is open")
        if let report = diagnosis.report {
            Text("Last diagnosis: \(report.capture.endedAt.formatted(date: .abbreviated, time: .shortened))")
        } else if diagnosis.errorMessage != nil {
            Text("Last diagnosis needs attention")
        }
        if let timestamp = model.snapshot?.date {
            Text("Last sample: \(timestamp.formatted(date: .omitted, time: .shortened))")
        }
        Text("RAM estimate: \(model.usedMemory)")
        Text("Pressure: \(model.snapshot?.pressure ?? "Measuring")")
        Text("\(model.portCount) open sockets · \(model.agentCount) agent processes")
        Divider()
        DaddyMenuOpenButton(appName: "PerformanceDaddy")
        Button(model.paused ? "Resume monitoring" : "Pause monitoring") { model.paused.toggle() }
        Toggle("Launch at Login", isOn: Binding(
            get: { launchAtLogin },
            set: { setLaunchAtLogin($0) }
        ))
        if let loginError { Text(loginError) }
        Toggle("Notify When Diagnosis Finishes", isOn: Binding(
            get: { notifyEnabled },
            set: { enabled in
                Task {
                    notifyEnabled = await DaddyCompletionNotices.setEnabled(enabled)
                    notificationError = enabled && !notifyEnabled
                }
            }
        ))
        if notificationError { Text("Enable notifications in System Settings.") }
        Button("Check for Updates…") { updates.check() }
            .disabled(!updates.canCheck || !updates.isIdle)
        Divider()
        DaddyMenuQuitButton(appName: "PerformanceDaddy")
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
            launchAtLogin = SMAppService.mainApp.status == .enabled
            loginError = nil
        } catch {
            launchAtLogin = SMAppService.mainApp.status == .enabled
            loginError = "Couldn’t change login setting. Check System Settings → Login Items."
        }
    }
}
