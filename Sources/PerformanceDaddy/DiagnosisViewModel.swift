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
    @Published private(set) var historyStorageError: String?

    private let recorder: DiagnosticRecorder
    private let engine = DiagnosticEngine()
    private let historyStore: DiagnosticHistoryStore
    private var recordingTask: Task<Void, Never>?
    private var historySaveTask: Task<Void, Never>?
    private var historyLoaded = false

    init(recorder: DiagnosticRecorder = DiagnosticRecorder(),
         historyStore: DiagnosticHistoryStore = DiagnosticHistoryStore()) {
        self.recorder = recorder
        self.historyStore = historyStore
        if CommandLine.arguments.contains("--preview-fixture") {
            let before = engine.analyze(DiagnosticFixtures.temporaryBuildCapture())
            let after = engine.analyze(DiagnosticFixtures.settledCapture())
            baselineReport = before
            report = after
            comparison = engine.compare(before: before, after: after)
            historyLoaded = true
        }
    }

    func loadHistory() async {
        guard !historyLoaded else { return }
        historyLoaded = true
        let captures = await historyStore.load()
        recentReports = captures.map(engine.analyze)
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
        persistHistory()
    }

    func review(_ previous: DiagnosticReport) {
        guard !isRecording else { return }
        report = previous
        baselineReport = nil
        comparison = nil
        errorMessage = nil
    }

    func waitForHistoryPersistence() async {
        await historySaveTask?.value
    }

    private func persistHistory() {
        let captures = recentReports.map(\.capture)
        let previous = historySaveTask
        let store = historyStore
        historySaveTask = Task { [weak self] in
            await previous?.value
            do {
                try await store.save(captures)
                await MainActor.run { self?.historyStorageError = nil }
            } catch {
                await MainActor.run {
                    self?.historyStorageError = "Recent runs could not be saved locally."
                }
            }
        }
    }
}
