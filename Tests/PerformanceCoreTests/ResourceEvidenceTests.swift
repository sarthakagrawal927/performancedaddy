import Foundation
@testable import PerformanceCore
import XCTest

final class ResourceEvidenceTests: XCTestCase {
    private func counter(_ time: Double, _ incoming: UInt64 = 100, _ outgoing: UInt64 = 200,
                         page: UInt64 = 16_384) -> SwapRateTracker.Counter {
        .init(time: time, pageSize: page, incoming: incoming, outgoing: outgoing)
    }

    func testSwapRatesUsePageSizeAndElapsedTime() throws {
        var tracker = SwapRateTracker()
        XCTAssertNil(tracker.update(counter(10)))
        let rate = try XCTUnwrap(tracker.update(counter(12, 104, 208)))
        XCTAssertEqual(rate.incoming, 32_768)
        XCTAssertEqual(rate.outgoing, 65_536)
        XCTAssertEqual(rate.interval, 2)
        let idle = try XCTUnwrap(tracker.update(counter(14, 104, 208)))
        XCTAssertEqual(idle.incoming, 0)
        XCTAssertEqual(idle.outgoing, 0)
    }

    func testMissingReadAndLongGapRequireFreshPair() {
        var tracker = SwapRateTracker()
        XCTAssertNil(tracker.update(counter(1)))
        XCTAssertNil(tracker.update(nil))
        XCTAssertNil(tracker.update(counter(3)))
        XCTAssertNotNil(tracker.update(counter(5)))
        XCTAssertNil(tracker.update(counter(100)))
        XCTAssertNotNil(tracker.update(counter(102)))
    }

    func testCounterResetPageChangeAndInvalidClocksDoNotProduceActivity() {
        for invalid in [counter(10), counter(9), counter(.nan), counter(.infinity),
                        counter(12, 99), counter(12, 100, 199), counter(12, page: 4096),
                        counter(12, page: 0)] {
            var tracker = SwapRateTracker()
            XCTAssertNil(tracker.update(counter(10)))
            XCTAssertNil(tracker.update(invalid))
        }
    }

    func testPowerPercentagesPreserveUnavailableAndRejectInvalidValues() {
        XCTAssertNil(PowerEvidence.percentage(nil))
        for value: Any in [true, -1, 101, 0.5, Double.nan, Double.infinity, "80"] {
            XCTAssertNil(PowerEvidence.percentage(value))
        }
        XCTAssertEqual(PowerEvidence.percentage(0), 0)
        XCTAssertEqual(PowerEvidence.percentage(80), 80)
        XCTAssertEqual(PowerEvidence.percentage(100), 100)
    }

    func testDiskCapacityCacheBoundsExpensiveReadsAndResetsAcrossGaps() {
        var cache = DiskCapacityCache()
        var reads = 0
        func read() -> Int64? { reads += 1; return Int64(reads) }
        let start = Date(timeIntervalSince1970: 1_000)
        XCTAssertEqual(cache.value(at: start, read: read), 1)
        XCTAssertEqual(cache.value(at: start.addingTimeInterval(59), read: read), 1)
        XCTAssertEqual(reads, 1)
        XCTAssertEqual(cache.value(at: start.addingTimeInterval(60), read: read), 2)
        XCTAssertEqual(cache.value(at: start.addingTimeInterval(-1), read: read), 3)
        cache.reset()
        XCTAssertEqual(cache.value(at: start, read: read), 4)
    }

    func testLiveNativeEvidenceDoesNotInventZeroOnFirstRate() async throws {
        let sampler = LiveSystemSampler()
        let sample = await sampler.sample(includeProcesses: false)
        let memory = try XCTUnwrap(sample.memory)
        XCTAssertNil(memory.swapInBytesPerSecond)
        XCTAssertNil(memory.swapOutBytesPerSecond)
        XCTAssertNil(memory.rateIntervalSeconds)
        XCTAssertLessThanOrEqual(memory.wiredBytes, ProcessInfo.processInfo.physicalMemory)
        XCTAssertNotNil(sample.power)
        XCTAssertTrue(sample.processes.isEmpty)
        await sampler.resetMeasurementWindow()
        let restarted = await sampler.sample(includeProcesses: false)
        XCTAssertNil(restarted.memory?.swapInBytesPerSecond)
        XCTAssertNil(restarted.memory?.swapOutBytesPerSecond)
        XCTAssertNil(restarted.usedCPUCores)
    }
}
