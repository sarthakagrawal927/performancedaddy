import AppKit
@testable import PerformanceCore
import SwiftUI
@testable import PerformanceDaddy
import XCTest

@MainActor
final class DesignEvidenceTests: XCTestCase {
    func testDashboardRendersAtSupportedNativeSizes() throws {
        let outputDirectory = ProcessInfo.processInfo.environment["PERFORMANCEDADDY_DESIGN_OUTPUT"]
        let specifications: [(label: Int, width: CGFloat, height: CGFloat)] = outputDirectory == nil
            ? [(390, 980, 800)]
            : [(390, 980, 800), (768, 1_096, 768), (1_440, 1_440, 900)]

        for specification in specifications {
            let model = LiveViewModel()
            model.snapshot = fixtureSnapshot()
            let view = NSHostingView(
                rootView: DashboardView(live: model)
                    .frame(width: specification.width, height: specification.height)
            )
            view.frame = NSRect(x: 0, y: 0, width: specification.width, height: specification.height)
            let window = NSWindow(contentRect: view.frame, styleMask: .borderless, backing: .buffered, defer: false)
            window.contentView = view
            view.layoutSubtreeIfNeeded()
            let representation = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
            view.cacheDisplay(in: view.bounds, to: representation)
            XCTAssertEqual(representation.size.width, specification.width)
            XCTAssertEqual(representation.size.height, specification.height)

            guard let outputDirectory else { continue }
            let directory = URL(fileURLWithPath: outputDirectory, isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let png = try XCTUnwrap(representation.representation(using: .png, properties: [:]))
            try png.write(to: directory.appendingPathComponent("after-\(specification.label).png"), options: .atomic)
        }
    }

    private func fixtureSnapshot() -> LiveSnapshot {
        let date = Date()
        let started = UInt64((date.timeIntervalSince1970 - 4_200) * 1_000_000)
        let processes = [
            LiveProcess(
                id: .init(pid: 4_201, started: started), parent: 1, uid: getuid(), name: "codex",
                executable: "/opt/homebrew/bin/codex", directory: "/Users/example/project",
                cpu: 18.4, memory: 482_000_000,
                ports: [.init(port: 3_000, transport: "TCP", address: "127.0.0.1", loopback: true)]
            ),
            LiveProcess(
                id: .init(pid: 4_202, started: started + 300_000_000), parent: 1, uid: getuid(), name: "BrowserDaddy",
                executable: "/Applications/BrowserDaddy.app/Contents/MacOS/BrowserDaddy", directory: "/",
                cpu: 3.1, memory: 228_000_000
            ),
            LiveProcess(
                id: .init(pid: 4_203, started: started + 600_000_000), parent: 1, uid: getuid(), name: "Xcode",
                executable: "/Applications/Xcode.app/Contents/MacOS/Xcode", directory: "/Users/example/project",
                cpu: 1.8, memory: 1_240_000_000
            ),
        ]
        let system = SystemSample(
            timestamp: date, usedCPUCores: 2.1, memoryHeadroomRatio: 0.42,
            swapUsedBytes: 0, diskFreeBytes: 512_000_000_000, thermal: .nominal,
            processes: []
        )
        return LiveSnapshot(
            date: date, processes: processes, system: system, pressure: "Normal",
            compressed: 1_100_000_000, unavailableProcesses: 0, portsDate: date, scanSeconds: 0.04
        )
    }
}
