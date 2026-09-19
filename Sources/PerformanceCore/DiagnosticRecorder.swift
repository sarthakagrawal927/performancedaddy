import Foundation

public actor DiagnosticRecorder {
    private let sampler: any SystemSampling

    public init(sampler: any SystemSampling = LiveSystemSampler()) {
        self.sampler = sampler
    }

    public func record(
        duration: TimeInterval,
        interval: TimeInterval = 1,
        progress: @escaping @Sendable (Double) -> Void = { _ in }
    ) async throws -> DiagnosticCapture {
        try Task.checkCancellation()
        await sampler.resetMeasurementWindow()
        let boundedDuration = duration.isFinite ? min(max(duration, 3), 600) : 15
        let boundedInterval = interval.isFinite ? min(max(interval, 0.5), 5) : 1
        let startedAt = Date()
        let deadline = startedAt.addingTimeInterval(boundedDuration)
        var samples: [SystemSample] = []
        samples.reserveCapacity(Int(boundedDuration / boundedInterval) + 2)

        while true {
            try Task.checkCancellation()
            samples.append(await sampler.sample())
            let elapsed = Date().timeIntervalSince(startedAt)
            progress(min(1, elapsed / boundedDuration))
            if Date() >= deadline { break }
            try await Task.sleep(for: .seconds(boundedInterval))
        }

        progress(1)
        return DiagnosticCapture(
            startedAt: startedAt,
            endedAt: Date(),
            samples: samples
        )
    }
}
