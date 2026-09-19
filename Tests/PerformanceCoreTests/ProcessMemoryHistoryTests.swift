import PerformanceCore
import XCTest

final class ProcessMemoryHistoryTests: XCTestCase {
    private func process(_ memory: UInt64, pid: Int32 = 42, started: UInt64 = 1) -> LiveProcess {
        LiveProcess(id: .init(pid: pid, started: started), parent: 1, uid: 501,
            name: "worker", executable: "/bin/worker", directory: "", cpu: nil, memory: memory)
    }

    func testGrowthRequiresDurationAndSubstantialAbsoluteAndRelativeChange() throws {
        var history = ProcessMemoryHistory()
        let mib: UInt64 = 1_024 * 1_024
        let first = process(512 * mib)
        history.observe([first], at: 0)
        XCTAssertNil(history.trend(for: first.id))
        history.observe([process(768 * mib)], at: 30)
        XCTAssertFalse(try XCTUnwrap(history.trend(for: first.id)).growing)
        history.observe([process(1024 * mib)], at: 60)
        let trend = try XCTUnwrap(history.trend(for: first.id))
        XCTAssertTrue(trend.growing)
        XCTAssertEqual(trend.delta, 512 * Int64(mib))
        XCTAssertEqual(trend.peak, 1024 * mib)
        history.observe([process(256 * mib)], at: 90)
        let declined = try XCTUnwrap(history.trend(for: first.id))
        XCTAssertFalse(declined.growing)
        XCTAssertEqual(declined.delta, -256 * Int64(mib))
        XCTAssertEqual(declined.peak, 1024 * mib)
    }

    func testGapsClockReversalAndInvalidTimeBreakContinuity() {
        let item = process(100)
        var history = ProcessMemoryHistory()
        for time in [0.0, 2] { history.observe([item], at: time) }
        XCTAssertNotNil(history.trend(for: item.id))
        history.observe([item], at: 33)
        XCTAssertNil(history.trend(for: item.id))
        history.observe([item], at: 32)
        XCTAssertNil(history.trend(for: item.id))
        history.observe([item], at: .nan)
        XCTAssertNil(history.trend(for: item.id))
    }

    func testExitReusedPIDAndExplicitResetDiscardHistory() {
        var history = ProcessMemoryHistory()
        let item = process(100)
        history.observe([item], at: 0)
        history.observe([item], at: 2)
        history.observe([process(200, started: 2)], at: 4)
        XCTAssertNil(history.trend(for: item.id))
        history.observe([item], at: 6)
        XCTAssertNil(history.trend(for: item.id))
        history.observe([item], at: 8)
        history.observe([], at: 10)
        XCTAssertNil(history.trend(for: item.id))
        history.observe([item], at: 12)
        history.observe([item], at: 14)
        history.reset()
        XCTAssertNil(history.trend(for: item.id))
    }

    func testRetentionAndProcessCaps() throws {
        var history = ProcessMemoryHistory()
        let processes = (1...513).map { process(UInt64($0), pid: Int32($0)) }
        for time in 0...200 { history.observe(processes, at: Double(time) * 2) }
        XCTAssertNil(history.trend(for: processes[0].id))
        let trend = try XCTUnwrap(history.trend(for: processes[512].id))
        XCTAssertEqual(trend.samples, 150)
        XCTAssertEqual(trend.seconds, 298)
    }
}
