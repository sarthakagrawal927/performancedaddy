import Foundation

public struct CauseAssessment: Identifiable, Equatable, Sendable {
    public enum Status: String, Equatable, Sendable {
        case observed = "Signal observed"
        case notObserved = "Threshold not met"
        case insufficient = "Insufficient evidence"
    }
    public let id: String
    public let title: String
    public let status: Status
    public let evidence: String
    public let limitation: String
}

public struct RootCauseAnalysis: Equatable, Sendable {
    public var headline: String {
        let signals = Set(assessments.filter { $0.status == .observed }.map(\.id))
        if signals.contains("thermal") { return "Thermal pressure needs investigation." }
        if signals.contains("memory") && signals.contains("paging") { return "Memory demand and paging need investigation." }
        if signals.contains("cpu") { return "CPU work is the strongest recorded signal." }
        if signals.contains("memory") { return "Low memory headroom needs a closer check." }
        if signals.contains("disk") { return "Low disk capacity needs review." }
        if signals.contains("paging") { return "Swap-out activity needs a closer check." }
        return "No measured signal explains the delay yet."
    }
    public let conclusion: String
    public let assessments: [CauseAssessment]
    public let contributors: [String]
    public let coverage: String
    public let nextCheck: String
    public let limitations: String

    public static func analyze(_ capture: DiagnosticCapture) -> Self {
        // Duplicate/out-of-window observations must not manufacture repeated evidence.
        var timestamps = Set<Date>()
        let samples = capture.samples.filter {
            $0.timestamp.timeIntervalSince1970.isFinite &&
            $0.timestamp >= capture.startedAt && $0.timestamp <= capture.endedAt &&
            timestamps.insert($0.timestamp).inserted
        }
        let count = samples.count
        let cpu = samples.compactMap(\.usedCPUCores).filter(valid)
        let headroom = samples.compactMap(\.memoryHeadroomRatio).filter { valid($0) && $0 <= 1 }
        let paging = samples.compactMap { $0.memory?.swapOutBytesPerSecond }.filter(valid)
        let thermal = samples.map(\.thermal).filter { $0 != .unavailable }
        let disk = samples.compactMap(\.diskFreeBytes).filter { $0 >= 0 }
        func covered(_ n: Int) -> Bool { n >= 2 && n * 5 >= count * 4 }
        func repeated(_ n: Int) -> Bool { n >= 2 && n * 2 >= count }
        func status(_ signal: Bool, _ validCount: Int) -> CauseAssessment.Status {
            signal ? .observed : covered(validCount) ? .notObserved : .insufficient
        }
        let cpuBusy = repeated(cpu.filter { $0 >= 1 }.count)
        let lowMemory = repeated(headroom.filter { $0 < 0.08 }.count)
        let swapping = repeated(paging.filter { $0 > 0 }.count)
        let hotCount = thermal.filter { $0 == .serious || $0 == .critical }.count
        let lowDisk = disk.contains { $0 < 20 * 1_024 * 1_024 * 1_024 }
        let cpuMean = cpu.isEmpty ? nil : cpu.reduce(0) { $0 + $1 / Double(cpu.count) }
        var assessments: [CauseAssessment] = [
            .init(id: "thermal", title: "Thermal pressure", status: status(hotCount > 0, thermal.count),
                  evidence: "Serious or critical state in \(hotCount)/\(count) samples; \(thermal.count) readable.",
                  limitation: "Thermal state does not identify the physical cause or prove it caused the reported delay."),
            .init(id: "memory", title: "Memory headroom", status: status(lowMemory, headroom.count),
                  evidence: "\(headroom.filter { $0 < 0.08 }.count)/\(count) samples below 8% estimated headroom; minimum \(headroom.min().map { number($0 * 100) + "%" } ?? "unavailable").",
                  limitation: "Free/inactive headroom is an estimate, not the macOS memory-pressure signal or proof of a leak."),
            .init(id: "paging", title: "Active swap-out", status: status(swapping, paging.count),
                  evidence: "Positive swap-out in \(paging.filter { $0 > 0 }.count)/\(count) samples; \(paging.count) readable rate samples.",
                  limitation: "Allocated swap is not active paging. Swap-out can contribute to delay, but no latency correlation was measured."),
            .init(id: "cpu", title: "CPU work", status: status(cpuBusy, cpu.count),
                  evidence: "Average \(cpuMean.map(number) ?? "unavailable") cores; peak \(cpu.max().map(number) ?? "unavailable"); \(cpu.count)/\(count) readable samples. \(cpu.filter { $0 >= 1 }.count)/\(count) samples at or above one core; the rule requires at least half the samples and at least two observations.",
                  limitation: "One core of activity is not whole-machine saturation. A blocked app can be slow while total CPU is low."),
            .init(id: "disk", title: "Disk capacity", status: status(lowDisk, disk.count),
                  evidence: "Minimum free space: \(disk.min().map { ByteCountFormatter.string(fromByteCount: $0, countStyle: .memory) } ?? "unavailable"); \(disk.count)/\(count) readable samples.",
                  limitation: "Below 20 GiB is a capacity review threshold, not proof of slow storage. Disk latency and throughput are not captured here."),
        ]
        // Signals first; preserve domain order within each tier.
        assessments = assessments.enumerated().sorted {
            let left = $0.element.status == .observed ? 0 : $0.element.status == .insufficient ? 1 : 2
            let right = $1.element.status == .observed ? 0 : $1.element.status == .insufficient ? 1 : 2
            return left == right ? $0.offset < $1.offset : left < right
        }.map(\.element)

        var totals: [String: Double] = [:]
        var appearances: [String: Int] = [:]
        for sample in samples {
            var names = Set<String>()
            for process in sample.processes where valid(process.cpuCores) {
                let name = String(process.name.filter { !$0.isNewline && !$0.isASCIIControl }.prefix(100))
                guard !name.isEmpty else { continue }
                // Divide before summation to avoid overflow on extreme finite inputs.
                totals[name, default: 0] += process.cpuCores / Double(max(count, 1))
                names.insert(name)
            }
            for name in names { appearances[name, default: 0] += 1 }
        }
        let contributors = totals.filter { $0.value.isFinite && $0.value > 0 }.sorted {
            $0.value == $1.value ? $0.key < $1.key : $0.value > $1.value
        }.prefix(3).map {
            "\($0.key): \(number($0.value)) recorded cores per sample; present in \(appearances[$0.key] ?? 0)/\(count) samples."
        }
        let conclusion: String
        let next: String
        if hotCount > 0 {
            conclusion = "Thermal pressure was observed and may be limiting performance. Its underlying cause is not established."
            next = "Keep airflow clear, allow cooling, then reproduce the same slow task and compare a recording of equal length. Check whether the task and thermal state both improve."
        } else if lowMemory && swapping {
            conclusion = "Low memory headroom and repeated swap-out activity were both observed in this recording. Memory demand is a candidate contributor, not a proven root cause."
            next = "Review the Memory view for a growing or unneeded app. If you choose to close one, save work first and repeat the same task and recording length; compare both paging and actual task delay."
        } else if cpuBusy {
            conclusion = contributors.isEmpty ?
                "Repeated CPU work was captured, but no positive readable process rows identify its owner. The cause of your task delay is not established." :
                "Repeated CPU work was captured. The named contributors explain recorded activity, but this does not yet prove why your task was slow."
            next = contributors.isEmpty ?
                "Repeat the slow action with the Processes view open and include system processes if needed. Process inspection may be restricted; a targeted profiler may be needed to identify the owner." :
                "Reproduce the delay while watching the named contributors. After a reviewed pause or completion of one workload, repeat the same task and equal-length recording to test whether the delay changes."
        } else {
            conclusion = "The root cause is not established by this recording. The assessment below shows exactly which signals were seen, absent at the rule threshold, or missing."
            next = lowMemory ? "Open Memory and check pressure and swap-rate trends while reproducing the delay; low headroom alone is not enough to justify stopping an app." :
                lowDisk ? "Review storage ownership in StorageDaddy before any cleanup. Reproduce the slow operation to distinguish a capacity concern from an actual I/O delay." :
                "For slow terminal opening, use Diagnose terminal startup. For another slow app, reproduce one specific action during a 2-minute check and inspect its process; network waits and app-internal blocking need targeted profiling."
        }
        let observer = samples.compactMap(\.samplerCPUCores).filter(valid).max()
        return Self(conclusion: conclusion, assessments: assessments, contributors: contributors,
                    coverage: "\(count) distinct in-window samples; \(capture.samples.count - count) invalid, duplicate or out-of-window samples excluded. Peak recorded observer CPU: \(observer.map(number) ?? "unavailable") cores.",
                    nextCheck: next,
                    limitations: "No causal intervention was performed. Process attribution includes at most the sampler's top 16 readable rows per sample, grouped by name—not verified app ownership. Missing rows are not proven idle; contributor averages are lower bounds of recorded work. Network latency, app hangs, GPU activity, disk latency and first-prompt timing are not measured by this recording. Non-observation only describes this window, not the absence of a problem.")
    }

    private static func valid(_ value: Double) -> Bool { value.isFinite && value >= 0 }
    private static func number(_ value: Double) -> String { String(format: "%.2f", value) }
}

private extension Character {
    var isASCIIControl: Bool { unicodeScalars.contains { $0.value < 32 || $0.value == 127 } }
}
