import Foundation
@testable import PerformanceCore
import XCTest

final class ProcessPresenceTests: XCTestCase {
    func testNativePresenceTracksOnlyOwnedChildIdentity() async throws {
        let child = Process()
        child.executableURL = URL(fileURLWithPath: "/bin/sleep")
        child.arguments = ["30"]
        try child.run()
        defer { if child.isRunning { child.terminate() } }
        let snapshot = await WorkloadSampler().sample()
        let observed = try XCTUnwrap(snapshot.processes.first { $0.id.pid == child.processIdentifier })
        XCTAssertEqual(ProcessPresence.inspect(observed.id), .observed)
        XCTAssertEqual(ProcessPresence.inspect(.init(pid: observed.id.pid, started: observed.id.started + 1)), .gone)
        XCTAssertEqual(ProcessPresence.inspect(.init(pid: 0, started: 10)), .unknown)
        XCTAssertEqual(ProcessPresence.inspect(.init(pid: -1, started: 10)), .unknown)
        XCTAssertEqual(ProcessPresence.inspect(.init(pid: observed.id.pid, started: 0)), .unknown)
        child.terminate()
        child.waitUntilExit()
        XCTAssertEqual(ProcessPresence.inspect(observed.id), .gone)
    }

    func testJournalConfirmsOnlyExplicitGoneEvidenceOnce() {
        let target = LiveProcess(id: .init(pid: 900, started: 10), parent: 1, uid: 501, name: "worker", executable: "/opt/bin/worker", directory: "", cpu: nil, memory: 0)
        let date = Date(timeIntervalSince1970: 100)
        var journal = ProcessLifecycleJournal()
        journal.record(target, at: date, force: false, signalSent: true, observed: [target])
        for status: ProcessPresence in [.unknown, .observed] {
            journal.confirmExit(target.id, presence: status, at: date)
            XCTAssertEqual(journal.events.count, 1)
            XCTAssertEqual(journal.pendingExitChecks, [target.id])
        }
        journal.confirmExit(target.id, presence: .gone, at: date)
        XCTAssertEqual(journal.events.count, 2)
        XCTAssertTrue(journal.events.last!.text.contains("Exit confirmed"))
        XCTAssertTrue(journal.pendingExitChecks.isEmpty)
        journal.confirmExit(target.id, presence: .gone, at: date)
        journal.observe([], at: date)
        XCTAssertEqual(journal.events.count, 2)
    }
}
