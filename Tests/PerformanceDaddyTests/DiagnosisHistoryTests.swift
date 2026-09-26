import Foundation
import PerformanceCore
import XCTest
@testable import PerformanceDaddy

@MainActor
final class DiagnosisHistoryTests: XCTestCase {
    func testEveryReportIsRetainedUpToTenAndReviewDoesNotRewriteHistory() async throws {
        let fixture = temporaryFile("diagnostic-history.json")
        defer { try? FileManager.default.removeItem(at: fixture.deletingLastPathComponent()) }
        let model = DiagnosisViewModel(historyStore: DiagnosticHistoryStore(fileURL: fixture))
        for index in 0..<12 {
            let capture = DiagnosticCapture(startedAt: Date(timeIntervalSince1970: Double(index)),
                                            endedAt: Date(timeIntervalSince1970: Double(index + 1)), samples: [])
            model.accept(DiagnosticEngine().analyze(capture))
        }
        XCTAssertEqual(model.recentReports.count, 10)
        XCTAssertEqual(model.recentReports.last?.capture.startedAt, Date(timeIntervalSince1970: 2))
        let oldest = model.recentReports.last!
        model.clearReport()
        XCTAssertNil(model.report)
        XCTAssertEqual(model.recentReports.count, 10)
        model.review(oldest)
        XCTAssertEqual(model.report, oldest)
        XCTAssertNil(model.comparison)
        XCTAssertNil(model.baselineReport)
        XCTAssertEqual(model.recentReports.first?.capture.startedAt, Date(timeIntervalSince1970: 11))
        XCTAssertEqual(model.report?.rootCauseAnalysis.assessments.count, 5)
        await model.waitForHistoryPersistence()
        let restarted = DiagnosisViewModel(historyStore: DiagnosticHistoryStore(fileURL: fixture))
        await restarted.loadHistory()
        XCTAssertEqual(restarted.recentReports.count, 10)
        XCTAssertEqual(restarted.recentReports.first?.capture.startedAt,
                       Date(timeIntervalSince1970: 11))
        XCTAssertEqual(restarted.recentReports.last?.capture.startedAt,
                       Date(timeIntervalSince1970: 2))
    }

    func testCorruptHistoryStartsEmptyWithoutDeletingTheFile() async throws {
        let fixture = temporaryFile("diagnostic-history.json")
        defer { try? FileManager.default.removeItem(at: fixture.deletingLastPathComponent()) }
        try FileManager.default.createDirectory(at: fixture.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        try Data("not-json".utf8).write(to: fixture)
        let model = DiagnosisViewModel(historyStore: DiagnosticHistoryStore(fileURL: fixture))
        await model.loadHistory()
        XCTAssertTrue(model.recentReports.isEmpty)
        XCTAssertEqual(try Data(contentsOf: fixture), Data("not-json".utf8))
    }

    func testKnownGoodBaselineSurvivesRecentRunDeletionUntilExplicitlyRemoved() async throws {
        let historyFile = temporaryFile("diagnostic-history.json")
        let baselineFile = historyFile.deletingLastPathComponent().appendingPathComponent("known-good-baseline.json")
        defer { try? FileManager.default.removeItem(at: historyFile.deletingLastPathComponent()) }
        let historyStore = DiagnosticHistoryStore(fileURL: historyFile)
        let baselineStore = KnownGoodBaselineStore(fileURL: baselineFile)
        let model = DiagnosisViewModel(historyStore: historyStore, baselineStore: baselineStore)
        let start = Date()
        let capture = DiagnosticCapture(startedAt: start, endedAt: start.addingTimeInterval(15), samples: [])
        let report = DiagnosticEngine().analyze(capture)
        model.accept(report)
        await model.waitForHistoryPersistence()
        await model.saveKnownGoodBaseline(report)
        XCTAssertEqual(model.savedBaselineReport?.capture.startedAt, start)

        let restarted = DiagnosisViewModel(historyStore: historyStore, baselineStore: baselineStore)
        await restarted.loadHistory()
        XCTAssertEqual(restarted.recentReports.count, 1)
        XCTAssertEqual(restarted.savedBaselineReport?.capture.startedAt, start)
        await restarted.deleteRecentRuns()
        XCTAssertTrue(restarted.recentReports.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: historyFile.path))
        XCTAssertEqual(restarted.savedBaselineReport?.capture.startedAt, start)

        await restarted.deleteKnownGoodBaseline()
        XCTAssertNil(restarted.savedBaselineReport)
        XCTAssertFalse(FileManager.default.fileExists(atPath: baselineFile.path))
    }

    private func temporaryFile(_ name: String) -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("performancedaddy-history-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent(name)
    }
}
