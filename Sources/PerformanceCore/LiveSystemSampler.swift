import Darwin
import Foundation

public protocol SystemSampling: Sendable {
    func sample() async -> SystemSample
    func resetMeasurementWindow() async
}

public actor LiveSystemSampler: SystemSampling {
    private struct ProcessCounter: Sendable {
        let totalNanoseconds: UInt64
        let observedAt: Date
    }

    private var previousCPUTicks: (busy: UInt64, total: UInt64)?
    private var previousProcessCounters: [Int32: ProcessCounter] = [:]
    private var processNames: [Int32: String] = [:]
    private var memoryReader = MemoryEvidenceReader()
    private var diskCapacity = DiskCapacityCache()

    public init() {}

    public func resetMeasurementWindow() async {
        memoryReader = MemoryEvidenceReader()
        diskCapacity.reset()
        previousCPUTicks = nil
        previousProcessCounters.removeAll()
    }

    public func sample() -> SystemSample {
        sample(includeProcesses: true)
    }

    public func sample(includeProcesses: Bool) -> SystemSample {
        let now = Date()
        let usedCPUCores = readUsedCPUCores()
        let processes = includeProcesses ? readProcesses(at: now) : []
        let samplerCPU = processes.first(where: { $0.id == getpid() })?.cpuCores
        let memory = memoryReader.read()
        let physical = ProcessInfo.processInfo.physicalMemory
        let headroom = memory.flatMap { value -> Double? in
            guard physical > 0 else { return nil }
            return min(1, (Double(value.freeBytes) + Double(value.inactiveBytes)) / Double(physical))
        }

        return SystemSample(
            timestamp: now,
            usedCPUCores: usedCPUCores,
            memoryHeadroomRatio: headroom,
            swapUsedBytes: readSwapUsed(),
            diskFreeBytes: diskCapacity.value(at: now, read: readDiskFree),
            thermal: readThermalCondition(),
            processes: Array(processes.prefix(16)),
            samplerCPUCores: samplerCPU,
            memory: memory,
            power: PowerEvidence.read()
        )
    }

    private func readUsedCPUCores() -> Double? {
        var cpuInfo: processor_info_array_t?
        var cpuCount: natural_t = 0
        var infoCount: mach_msg_type_number_t = 0
        let result = host_processor_info(
            mach_host_self(),
            PROCESSOR_CPU_LOAD_INFO,
            &cpuCount,
            &cpuInfo,
            &infoCount
        )
        guard result == KERN_SUCCESS, let cpuInfo else { return nil }
        defer {
            vm_deallocate(
                mach_task_self_,
                vm_address_t(UInt(bitPattern: cpuInfo)),
                vm_size_t(Int(infoCount) * MemoryLayout<integer_t>.stride)
            )
        }

        let values = UnsafeBufferPointer(start: cpuInfo, count: Int(infoCount))
        var busy: UInt64 = 0
        var total: UInt64 = 0
        for cpu in 0..<Int(cpuCount) {
            let offset = cpu * Int(CPU_STATE_MAX)
            let user = UInt64(values[offset + Int(CPU_STATE_USER)])
            let system = UInt64(values[offset + Int(CPU_STATE_SYSTEM)])
            let nice = UInt64(values[offset + Int(CPU_STATE_NICE)])
            let idle = UInt64(values[offset + Int(CPU_STATE_IDLE)])
            busy += user + system + nice
            total += user + system + nice + idle
        }

        let current = (busy: busy, total: total)
        defer { previousCPUTicks = current }
        guard let previousCPUTicks,
              total > previousCPUTicks.total,
              busy >= previousCPUTicks.busy
        else { return nil }

        let busyDelta = Double(busy - previousCPUTicks.busy)
        let totalDelta = Double(total - previousCPUTicks.total)
        return (busyDelta / totalDelta) * Double(cpuCount)
    }

    private func readProcesses(at now: Date) -> [ProcessObservation] {
        var pids = [pid_t](repeating: 0, count: 8_192)
        let bytes = pids.withUnsafeMutableBytes { buffer in
            proc_listallpids(buffer.baseAddress, Int32(buffer.count))
        }
        guard bytes > 0 else { return [] }

        let pidCount = min(Int(bytes), pids.count)
        var nextCounters: [Int32: ProcessCounter] = [:]
        var observations: [ProcessObservation] = []
        observations.reserveCapacity(16)

        for pid in pids.prefix(pidCount) where pid > 0 {
            var taskInfo = proc_taskinfo()
            let taskBytes = proc_pidinfo(
                pid,
                PROC_PIDTASKINFO,
                0,
                &taskInfo,
                Int32(MemoryLayout<proc_taskinfo>.stride)
            )
            guard taskBytes == MemoryLayout<proc_taskinfo>.stride else { continue }

            let total = taskInfo.pti_total_user &+ taskInfo.pti_total_system
            nextCounters[pid] = ProcessCounter(totalNanoseconds: total, observedAt: now)

            guard let previous = previousProcessCounters[pid],
                  total >= previous.totalNanoseconds
            else { continue }
            let elapsed = now.timeIntervalSince(previous.observedAt)
            guard elapsed > 0 else { continue }
            var timebase = mach_timebase_info_data_t()
            mach_timebase_info(&timebase)
            let cores = Double(total - previous.totalNanoseconds) * Double(timebase.numer) / Double(timebase.denom) / 1_000_000_000 / elapsed
            guard cores >= 0.005 else { continue }

            var bsdInfo = proc_bsdinfo()
            let bsdBytes = proc_pidinfo(
                pid,
                PROC_PIDTBSDINFO,
                0,
                &bsdInfo,
                Int32(MemoryLayout<proc_bsdinfo>.stride)
            )
            let parentID = bsdBytes == MemoryLayout<proc_bsdinfo>.stride ? Int32(bsdInfo.pbi_ppid) : 0
            let name = processNames[pid] ?? processName(pid: pid)
            if !name.isEmpty { processNames[pid] = name }
            let observation = ProcessObservation(
                id: pid,
                parentID: parentID,
                name: name.isEmpty ? "Process \(pid)" : name,
                cpuCores: min(cores, Double(ProcessInfo.processInfo.activeProcessorCount)),
                residentBytes: taskInfo.pti_resident_size
            )
            insertIntoTopProcesses(observation, in: &observations)
        }

        previousProcessCounters = nextCounters
        processNames = processNames.filter { nextCounters[$0.key] != nil }
        return observations.sorted {
            if $0.cpuCores == $1.cpuCores { return $0.residentBytes > $1.residentBytes }
            return $0.cpuCores > $1.cpuCores
        }
    }

    private func insertIntoTopProcesses(
        _ observation: ProcessObservation,
        in observations: inout [ProcessObservation]
    ) {
        guard observations.count >= 16 else {
            observations.append(observation)
            return
        }
        guard let lightestIndex = observations.indices.min(by: {
            observations[$0].cpuCores < observations[$1].cpuCores
        }), observation.cpuCores > observations[lightestIndex].cpuCores else { return }
        observations[lightestIndex] = observation
    }

    private func processName(pid: pid_t) -> String {
        var bytes = [CChar](repeating: 0, count: Int(MAXPATHLEN))
        let length = proc_name(pid, &bytes, UInt32(bytes.count))
        guard length > 0 else { return "" }
        return String(cString: bytes)
    }

    private func readSwapUsed() -> UInt64? {
        var usage = xsw_usage()
        var size = MemoryLayout<xsw_usage>.stride
        guard sysctlbyname("vm.swapusage", &usage, &size, nil, 0) == 0 else { return nil }
        return usage.xsu_used
    }

    private func readDiskFree() -> Int64? {
        let home = URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
        let values = try? home.resourceValues(forKeys: [
            .volumeAvailableCapacityForImportantUsageKey,
            .volumeAvailableCapacityKey,
        ])
        return values?.volumeAvailableCapacityForImportantUsage
            ?? values?.volumeAvailableCapacity.map(Int64.init)
    }

    private func readThermalCondition() -> ThermalCondition {
        switch ProcessInfo.processInfo.thermalState {
        case .nominal: .nominal
        case .fair: .fair
        case .serious: .serious
        case .critical: .critical
        @unknown default: .unavailable
        }
    }
}
