import Foundation
import XCTest
@testable import PerformanceCore

final class DiagnosticRecorderTests: XCTestCase {
    func testEachRecordingResetsRateWindowBeforeFirstSample() async throws {
        let sampler = ResetRecordingSampler()
        let recorder = DiagnosticRecorder(sampler: sampler)
        let first = try await recorder.record(duration: 3, interval: 0.5)
        let second = try await recorder.record(duration: 3, interval: 0.5)
        XCTAssertNil(first.samples.first?.usedCPUCores)
        XCTAssertNil(second.samples.first?.usedCPUCores)
        XCTAssertEqual(second.samples.dropFirst().first?.usedCPUCores, 0.2)
        let resets = await sampler.resets
        XCTAssertEqual(resets, 2)
    }
}

private actor ResetRecordingSampler: SystemSampling {
    private(set) var resets = 0
    private var fresh = false
    func resetMeasurementWindow() async { resets += 1; fresh = true }
    func sample() -> SystemSample {
        defer { fresh = false }
        return .init(timestamp: Date(), usedCPUCores: fresh ? nil : 0.2,
                     memoryHeadroomRatio: 0.5, swapUsedBytes: 0, diskFreeBytes: nil,
                     thermal: .nominal, processes: [])
    }
}
