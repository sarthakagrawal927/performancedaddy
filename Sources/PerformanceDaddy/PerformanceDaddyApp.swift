import SwiftUI

@main
struct PerformanceDaddyApp: App {
    @NSApplicationDelegateAdaptor(PerformanceDaddyDelegate.self) private var delegate
    @StateObject private var live = LiveViewModel()
    var body: some Scene {
        WindowGroup(id: "main") {
            DashboardView(live: live)
                .frame(minWidth: 980, minHeight: 800)
        }
        .defaultSize(width: 1_180, height: 800)
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(replacing: .newItem) {}
        }
        MenuBarExtra {
            LiveMenu(model: live)
        } label: {
            Label(live.usedMemory, systemImage: "memorychip")
        }
    }
}

@MainActor
final class PerformanceDaddyDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        if let icon = PerformanceAppIcon.image { NSApplication.shared.applicationIconImage = icon }
    }
}

@MainActor
enum PerformanceAppIcon {
    static let image = Bundle.module.url(forResource: "PerformanceDaddy", withExtension: "png").flatMap(NSImage.init(contentsOf:))
}

private struct LiveMenu: View {
    @ObservedObject var model: LiveViewModel
    @Environment(\.openWindow) private var openWindow
    var body: some View {
        Text("RAM estimate: \(model.usedMemory)")
        Text("Pressure: \(model.snapshot?.pressure ?? "Measuring")")
        Text("\(model.portCount) open sockets · \(model.agentCount) agent processes")
        Divider()
        Button("Open PerformanceDaddy") {
            openWindow(id: "main")
            NSApplication.shared.activate(ignoringOtherApps: true)
        }
        Button(model.paused ? "Resume monitoring" : "Pause monitoring") { model.paused.toggle() }
        Divider()
        Button("Quit PerformanceDaddy") { NSApplication.shared.terminate(nil) }
    }
}
