import Foundation
@testable import PerformanceCore
import XCTest

final class ProcessCatalogTests: XCTestCase {
    func testEvidenceKeyChangesAcrossExecAndCredentialChanges() {
        func process(_ executable: String, uid: UInt32 = 501) -> LiveProcess {
            LiveProcess(id: .init(pid: 100, started: 10), parent: 1, uid: uid, name: "worker", executable: executable, directory: "", cpu: nil, memory: 0)
        }
        XCTAssertEqual(ProcessEvidenceKey(process("/bin/sleep")), ProcessEvidenceKey(process("/bin/sleep")))
        XCTAssertNotEqual(ProcessEvidenceKey(process("/bin/sleep")), ProcessEvidenceKey(process("/tmp/worker")))
        XCTAssertNotEqual(ProcessEvidenceKey(process("/bin/sleep")), ProcessEvidenceKey(process("/bin/sleep", uid: 502)))
    }
    func testCancelledValidationDoesNotProduceEvidence() async throws {
        let snapshot = await WorkloadSampler().sample()
        let own = try XCTUnwrap(snapshot.processes.first { $0.id.pid == ProcessInfo.processInfo.processIdentifier })
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return await ProcessCodeIdentityReader.shared.inspect(own)
        }
        let result = await task.value
        XCTAssertEqual(result.status, .unavailable)
        XCTAssertNil(result.identifier)
        XCTAssertEqual(result.seconds, 0)
    }
    func testAncestryIsNearestFirstCycleSafeAndRejectsReusedParent() {
        func item(_ pid: Int32, parent: Int32, start: UInt64) -> LiveProcess {
            LiveProcess(id: .init(pid: pid, started: start), parent: parent, uid: 501, name: "worker", executable: "/bin/worker", directory: "", cpu: nil, memory: 0)
        }
        let app = item(10, parent: 1, start: 10)
        let shell = item(11, parent: 10, start: 20)
        let worker = item(12, parent: 11, start: 30)
        XCTAssertEqual(WorkloadIndex([app, shell, worker]).ancestors(of: worker).map(\.id.pid), [11, 10])
        XCTAssertTrue(WorkloadIndex([item(11, parent: 1, start: 40), worker]).ancestors(of: worker).isEmpty)
        let cyclic = [item(10, parent: 11, start: 1), item(11, parent: 10, start: 1)]
        XCTAssertEqual(WorkloadIndex(cyclic).ancestors(of: cyclic[0]).count, 1)
    }
    func testCatalogHasUniqueSourcedEntriesAndRejectsLookalikes() {
        XCTAssertEqual(ProcessCatalog.entries.count, 37)
        XCTAssertEqual(Set(ProcessCatalog.entries.map(\.name)).count, 37)
        for entry in ProcessCatalog.entries {
            XCTAssertFalse(entry.role.isEmpty)
            XCTAssertTrue(entry.source.contains("\(entry.name)(8)"))
            XCTAssertEqual(ProcessCatalog.match(executable: "/usr/libexec/\(entry.name)")?.name, entry.name)
            for path in ["/tmp/\(entry.name)", "/usr/libexec/\(entry.name)-fake", "/System/LibraryFake/\(entry.name)", "/System/Library/../\(entry.name)", "/usr/libexec/./\(entry.name)"] {
                XCTAssertNil(ProcessCatalog.match(executable: path), path)
            }
        }
    }

    func testCodeEvidenceNeverAuthenticatesFailedOrUnstableObservations() {
        for (valid, stable) in [(false, true), (true, false), (false, false)] {
            let value = ProcessCodeIdentity.result(valid: valid, apple: true, developer: true, team: "TEAM", identifier: "id", stable: stable)
            XCTAssertEqual(value.status, .unavailable)
            XCTAssertNil(value.team)
            XCTAssertNil(value.identifier)
        }
        let selfSigned = ProcessCodeIdentity.result(valid: true, apple: false, developer: false, team: "CLAIM", identifier: "id", stable: true)
        XCTAssertEqual(selfSigned.status, .unattributed)
        XCTAssertNil(selfSigned.team)
        XCTAssertEqual(ProcessCodeIdentity.result(valid: true, apple: true, developer: false, team: nil, identifier: "com.apple.test", stable: true).status, .apple)
        XCTAssertEqual(ProcessCodeIdentity.result(valid: true, apple: false, developer: true, team: "TEAM", identifier: "id", stable: true).status, .developer)
        XCTAssertEqual(ProcessCodeIdentity.result(valid: true, apple: false, developer: true, team: "", identifier: "id", stable: true).status, .unattributed)
    }

    func testNativeValidationRejectsReusedIdentity() async throws {
        let snapshot = await WorkloadSampler().sample()
        let own = try XCTUnwrap(snapshot.processes.first { $0.id.pid == ProcessInfo.processInfo.processIdentifier })
        let stale = LiveProcess(id: .init(pid: own.id.pid, started: own.id.started + 1), parent: own.parent,
            uid: own.uid, name: own.name, executable: own.executable, directory: "", cpu: nil, memory: 0)
        XCTAssertEqual(ProcessCodeIdentity.inspect(stale).status, .unavailable)
    }

    func testAppleOwnedTestChildHasValidatedCodeIdentity() async throws {
        let child = Process()
        child.executableURL = URL(fileURLWithPath: "/bin/sleep")
        child.arguments = ["30"]
        try child.run()
        defer { if child.isRunning { child.terminate() } }
        let snapshot = await WorkloadSampler().sample()
        let observed = try XCTUnwrap(snapshot.processes.first { $0.id.pid == child.processIdentifier })
        let evidence = ProcessCodeIdentity.inspect(observed)
        XCTAssertEqual(evidence.status, .apple)
        XCTAssertNotNil(evidence.identifier)
    }
}
