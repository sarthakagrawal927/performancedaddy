import Foundation
import PerformanceCore
import XCTest

final class DiagnosticEngineTests: XCTestCase {
    private let engine = DiagnosticEngine()

    func testAllocatedSwapAloneDoesNotDiagnoseMemoryPressure() {
        let result = engine.analyze(capture(samples: [
            sample(at: 0, cores: 0.2, headroom: 0.5, swap: 8_000_000_000, thermal: .nominal),
            sample(at: 1, cores: 0.3, headroom: 0.5, swap: 8_000_000_000, thermal: .nominal),
        ]))
        XCTAssertEqual(result.finding.kind, .healthy)
        XCTAssertFalse(result.finding.summary.contains("active swap"))
    }

    func testSingleHeadroomSpikeDoesNotBecomeSustainedPressure() {
        let result = engine.analyze(capture(samples: [
            sample(at: 0, cores: 0.2, headroom: 0.5, swap: 0, thermal: .nominal),
            sample(at: 1, cores: 0.3, headroom: 0.01, swap: 0, thermal: .nominal),
            sample(at: 2, cores: 0.2, headroom: 0.5, swap: 0, thermal: .nominal),
        ]))
        XCTAssertEqual(result.finding.kind, .inconclusive)
    }

    func testMixedComparisonDoesNotClaimImprovement() {
        let before = engine.analyze(capture(samples: [
            sample(at: 0, cores: 3, headroom: 0.5, swap: 0, thermal: .nominal),
            sample(at: 1, cores: 3, headroom: 0.5, swap: 0, thermal: .nominal),
        ]))
        let after = engine.analyze(capture(samples: [
            sample(at: 0, cores: 0.2, headroom: 0.05, swap: 0, thermal: .nominal),
            sample(at: 1, cores: 0.2, headroom: 0.05, swap: 0, thermal: .nominal),
        ]))
        XCTAssertEqual(engine.compare(before: before, after: after).outcome, .inconclusive)
    }

    func testMissingAndNonfiniteEvidenceNeverBecomesHealthy() {
        let partial = (0..<2).map { offset in
            SystemSample(timestamp: Date(timeIntervalSince1970: Double(offset)), usedCPUCores: 0.1,
                memoryHeadroomRatio: .nan, swapUsedBytes: nil, diskFreeBytes: nil, thermal: .unavailable, processes: [])
        }
        let result = engine.analyze(capture(samples: partial))
        XCTAssertEqual(result.finding.kind, .inconclusive)
        XCTAssertEqual(engine.compare(before: result, after: result).outcome, .inconclusive)
        let invalidCPU = (0..<2).map { offset in
            SystemSample(timestamp: Date(timeIntervalSince1970: Double(offset)), usedCPUCores: .infinity,
                memoryHeadroomRatio: 0.5, swapUsedBytes: 0, diskFreeBytes: nil, thermal: .nominal, processes: [])
        }
        XCTAssertEqual(engine.analyze(capture(samples: invalidCPU)).finding.kind, .inconclusive)
    }

    func testPartialMemoryReadDoesNotHideThermalWorsening() {
        let before = engine.analyze(capture(samples: [
            sample(at: 0, cores: 3, headroom: 0.5, swap: 0, thermal: .nominal),
            sample(at: 1, cores: 3, headroom: 0.5, swap: 0, thermal: .nominal),
        ]))
        let after = engine.analyze(capture(samples: [
            sample(at: 0, cores: 0.2, headroom: 0.5, swap: 0, thermal: .nominal),
            sample(at: 1, cores: 0.2, headroom: 0.5, swap: 0, thermal: .nominal),
            SystemSample(timestamp: Date(timeIntervalSince1970: 2), usedCPUCores: 0.2,
                memoryHeadroomRatio: nil, swapUsedBytes: nil, diskFreeBytes: nil, thermal: .critical, processes: []),
        ]))
        XCTAssertEqual(engine.compare(before: before, after: after).outcome, .inconclusive)
    }

    func testMismatchedCaptureDurationsDoNotProduceImprovement() {
        let a = engine.analyze(DiagnosticFixtures.temporaryBuildCapture())
        let b = engine.analyze(DiagnosticFixtures.settledCapture())
        XCTAssertEqual(engine.compare(before: a, after: b).outcome, .inconclusive)
    }

    func testTemporaryBuildLoadUsesHealthyCounterEvidence() {
        let report = engine.analyze(DiagnosticFixtures.temporaryBuildCapture())

        XCTAssertEqual(report.finding.kind, .temporaryBuildLoad)
        XCTAssertEqual(report.finding.confidence, .medium)
        XCTAssertTrue(report.finding.verdict.contains("Development tools"))
        XCTAssertTrue(report.finding.whyDetail.contains("Spotlight"))
        XCTAssertEqual(report.finding.evidence.first(where: { $0.id == "swap" })?.isHealthy, true)
    }

    func testMemoryPressureOutranksOrdinaryProcessLoad() {
        let capture = capture(samples: [
            sample(at: 0, cores: 3, headroom: 0.06, swap: 900_000_000, thermal: .nominal),
            sample(at: 1, cores: 2.5, headroom: 0.05, swap: 1_000_000_000, thermal: .nominal),
            sample(at: 2, cores: 2, headroom: 0.07, swap: 1_000_000_000, thermal: .nominal),
        ])

        XCTAssertEqual(engine.analyze(capture).finding.kind, .memoryPressure)
    }

    func testThermalPressureOutranksMemoryAndCPU() {
        let capture = capture(samples: [
            sample(at: 0, cores: 4, headroom: 0.05, swap: 1_000_000_000, thermal: .serious),
            sample(at: 1, cores: 4, headroom: 0.05, swap: 1_000_000_000, thermal: .critical),
        ])

        XCTAssertEqual(engine.analyze(capture).finding.kind, .thermalPressure)
    }

    func testHealthyCaptureDoesNotInventCause() {
        let capture = capture(samples: [
            sample(at: 0, cores: 0.2, headroom: 0.55, swap: 0, thermal: .nominal),
            sample(at: 1, cores: 0.4, headroom: 0.52, swap: 0, thermal: .nominal),
            sample(at: 2, cores: 0.3, headroom: 0.51, swap: 0, thermal: .nominal),
        ])

        let finding = engine.analyze(capture).finding
        XCTAssertEqual(finding.kind, .healthy)
        XCTAssertTrue(finding.whyDetail.contains("will not guess"))
    }

    func testSingleSampleIsInconclusive() {
        let capture = capture(samples: [
            sample(at: 0, cores: 8, headroom: 0.5, swap: 0, thermal: .nominal),
        ])

        let finding = engine.analyze(capture).finding
        XCTAssertEqual(finding.kind, .inconclusive)
        XCTAssertEqual(finding.confidence, .low)
    }

    func testComparisonPreservesBeforeAndReportsImprovement() {
        let before = engine.analyze(capture(samples: [
            sample(at: 0, cores: 2.8, headroom: 0.08, swap: 800_000_000, thermal: .nominal),
            sample(at: 1, cores: 2.4, headroom: 0.07, swap: 700_000_000, thermal: .nominal),
        ]))
        let after = engine.analyze(capture(samples: [
            sample(at: 0, cores: 0.3, headroom: 0.42, swap: 0, thermal: .nominal),
            sample(at: 1, cores: 0.4, headroom: 0.44, swap: 0, thermal: .nominal),
        ]))

        let comparison = engine.compare(before: before, after: after)
        XCTAssertEqual(comparison.outcome, .improved)
        XCTAssertLessThan(comparison.cpuDelta ?? 0, 0)
        XCTAssertGreaterThan(comparison.memoryHeadroomDelta ?? 0, 0)
    }

    func testComparisonUsesThresholdForUnchangedEvidence() {
        let before = engine.analyze(capture(samples: [
            sample(at: 0, cores: 0.30, headroom: 0.50, swap: 0, thermal: .nominal),
            sample(at: 1, cores: 0.35, headroom: 0.49, swap: 0, thermal: .nominal),
        ]))
        let after = engine.analyze(capture(samples: [
            sample(at: 0, cores: 0.36, headroom: 0.48, swap: 0, thermal: .nominal),
            sample(at: 1, cores: 0.38, headroom: 0.48, swap: 0, thermal: .nominal),
        ]))

        XCTAssertEqual(engine.compare(before: before, after: after).outcome, .unchanged)
    }

    private func capture(samples: [SystemSample]) -> DiagnosticCapture {
        DiagnosticCapture(
            startedAt: samples.first?.timestamp ?? .distantPast,
            endedAt: samples.last?.timestamp ?? .distantPast,
            samples: samples
        )
    }

    private func sample(
        at offset: TimeInterval,
        cores: Double,
        headroom: Double,
        swap: UInt64,
        thermal: ThermalCondition
    ) -> SystemSample {
        SystemSample(
            timestamp: Date(timeIntervalSince1970: 1_000 + offset),
            usedCPUCores: cores,
            memoryHeadroomRatio: headroom,
            swapUsedBytes: swap,
            diskFreeBytes: 100 * 1_024 * 1_024 * 1_024,
            thermal: thermal,
            processes: [],
            samplerCPUCores: 0.01
        )
    }
}
