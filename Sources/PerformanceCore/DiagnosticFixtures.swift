import Foundation

public enum DiagnosticFixtures {
    public static func temporaryBuildCapture() -> DiagnosticCapture {
        let start = Date(timeIntervalSince1970: 1_789_752_000)
        let cores = [1.2, 2.8, 5.1, 7.6, 9.7, 8.9, 8.1, 6.4, 4.2]
        let samples = cores.enumerated().map { index, cores in
            SystemSample(
                timestamp: start.addingTimeInterval(Double(index) * 15),
                usedCPUCores: cores,
                memoryHeadroomRatio: 0.91,
                swapUsedBytes: 0,
                diskFreeBytes: 330 * 1_024 * 1_024 * 1_024,
                thermal: .nominal,
                processes: [
                    ProcessObservation(
                        id: 41_820,
                        parentID: 41_819,
                        name: "npm ci",
                        cpuCores: cores * 0.18,
                        residentBytes: 580 * 1_024 * 1_024
                    ),
                    ProcessObservation(
                        id: 41_823,
                        parentID: 41_820,
                        name: "node",
                        cpuCores: cores * 0.67,
                        residentBytes: 690 * 1_024 * 1_024
                    ),
                    ProcessObservation(
                        id: 578,
                        parentID: 1,
                        name: "mds_stores",
                        cpuCores: index >= 3 ? 0.22 : 0.02,
                        residentBytes: 340 * 1_024 * 1_024
                    ),
                ],
                samplerCPUCores: 0.01
            )
        }
        return DiagnosticCapture(
            startedAt: start,
            endedAt: start.addingTimeInterval(120),
            samples: samples,
            isFixture: true
        )
    }

    public static func settledCapture() -> DiagnosticCapture {
        let start = Date(timeIntervalSince1970: 1_789_752_180)
        let cores = [0.7, 0.5, 0.6, 0.4, 0.5, 0.4]
        let samples = cores.enumerated().map { index, cores in
            SystemSample(
                timestamp: start.addingTimeInterval(Double(index) * 3),
                usedCPUCores: cores,
                memoryHeadroomRatio: 0.90,
                swapUsedBytes: 0,
                diskFreeBytes: 330 * 1_024 * 1_024 * 1_024,
                thermal: .nominal,
                processes: [],
                samplerCPUCores: 0.01
            )
        }
        return DiagnosticCapture(
            startedAt: start,
            endedAt: start.addingTimeInterval(15),
            samples: samples,
            isFixture: true
        )
    }
}
