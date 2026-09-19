import Foundation
import PerformanceCore
import XCTest
@testable import PerformanceDaddy

@MainActor
final class DiagnosisHistoryTests: XCTestCase {
    func testEveryReportIsRetainedUpToTenAndReviewDoesNotRewriteHistory() {
        let model = DiagnosisViewModel()
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
    }
}
