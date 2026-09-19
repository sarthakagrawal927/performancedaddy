import Combine
import Foundation
import PerformanceCore

@MainActor
final class DiagnosisViewModel: ObservableObject {
    enum CaptureLength: String, CaseIterable, Identifiable {
        case quick = "15 sec"
        case standard = "2 min"

        var id: Self { self }
        var seconds: TimeInterval {
            switch self {
            case .quick: 15
            case .standard: 120
            }
        }
    }

    @Published var selectedLength: CaptureLength = .quick
    @Published private(set) var report: DiagnosticReport?
    @Published private(set) var baselineReport: DiagnosticReport?
    @Published private(set) var comparison: DiagnosticComparison?
    @Published private(set) var isRecording = false
    @Published private(set) var progress = 0.0
    @Published private(set) var errorMessage: String?
    @Published private(set) var recentReports: [DiagnosticReport] = []

    private let recorder: DiagnosticRecorder
    private let engine = DiagnosticEngine()
    private var recordingTask: Task<Void, Never>?

    init(recorder: DiagnosticRecorder = DiagnosticRecorder()) {
        self.recorder = recorder
        if CommandLine.arguments.contains("--preview-fixture") {
            let before = engine.analyze(DiagnosticFixtures.temporaryBuildCapture())
            let after = engine.analyze(DiagnosticFixtures.settledCapture())
            baselineReport = before
            report = after
            comparison = engine.compare(before: before, after: after)
        }
    }

    func startRecording() {
        beginRecording(preservingCurrentReport: false)
    }

    func performRecommendedAction() {
        if report?.finding.kind == .healthy || report?.finding.kind == .inconclusive {
            selectedLength = .standard
        }
        beginRecording(preservingCurrentReport: true)
    }

    private func beginRecording(preservingCurrentReport: Bool) {
        recordingTask?.cancel()
        let previous = preservingCurrentReport ? report : nil
        baselineReport = previous
        comparison = nil
        isRecording = true
        progress = 0
        errorMessage = nil
        report = nil
        let duration = selectedLength.seconds

        recordingTask = Task { [weak self] in
            guard let self else { return }
            do {
                let capture = try await recorder.record(duration: duration) { [weak self] value in
                    Task { @MainActor in self?.progress = value }
                }
                let nextReport = engine.analyze(capture)
                accept(nextReport)
                if let previous {
                    comparison = engine.compare(before: previous, after: nextReport)
                }
            } catch is CancellationError {
                errorMessage = "The recording was cancelled. No changes were made."
                report = previous
            } catch {
                errorMessage = "The recording could not finish: \(error.localizedDescription)"
                report = previous
            }
            isRecording = false
        }
    }

    func cancelRecording() {
        recordingTask?.cancel()
        recordingTask = nil
    }

    func clearReport() {
        report = nil
        baselineReport = nil
        comparison = nil
        errorMessage = nil
        progress = 0
    }

    func accept(_ completed: DiagnosticReport) {
        report = completed
        recentReports.insert(completed, at: 0)
        if recentReports.count > 10 { recentReports.removeLast(recentReports.count - 10) }
    }

    func review(_ previous: DiagnosticReport) {
        guard !isRecording else { return }
        report = previous
        baselineReport = nil
        comparison = nil
        errorMessage = nil
    }
}
