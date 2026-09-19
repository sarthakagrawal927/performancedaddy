import Foundation

/// Deliberately separate from runtime models: adding a sensor never silently
/// expands the export's privacy surface. No names, paths, raw PIDs or addresses.
public enum SnapshotExport {
    private struct Document: Encodable {
        let schema = "performancedaddy.snapshot.v1"
        let capturedAt: Date
        let socketSampleAt: Date
        let physicalMemoryBytes: UInt64
        let memoryHeadroomRatio: Double?
        let systemCPUCores: Double?
        let pressure: String
        let swapBytes: UInt64?
        let compressedBytes: UInt64?
        let memoryEvidence: MemoryRecord?
        let powerEvidence: PowerRecord?
        let thermal: ThermalCondition
        let scanSeconds: Double?
        let unavailableProcesses: Int
        let processes: [ProcessRecord]
        let privacy = "Process names, executable/project paths, raw PIDs, start times and bind addresses omitted. Aliases apply only within this snapshot."
        let limits = "Resident memory includes shared pages. CPU 100% is one logical core. Agent labels identify local executable metadata, not conversation status. This snapshot does not prove a cause or an improvement."
    }
    private struct ProcessRecord: Encodable {
        let alias: String
        let parentAlias: String?
        let agent: String?
        let cpuPercent: Double?
        let residentBytes: UInt64
        let ports: [PortRecord]
        let portsIncomplete: Bool
    }
    private struct PortRecord: Encodable {
        let number: UInt16
        let transport: String
        let scope: String
    }
    private struct MemoryRecord: Encodable {
        let freeBytes: UInt64
        let inactiveBytes: UInt64
        let wiredBytes: UInt64
        let fileBackedBytes: UInt64
        let compressedBytes: UInt64
        let swapInBytesPerSecond: Double?
        let swapOutBytesPerSecond: Double?
        let rateIntervalSeconds: Double?
        let limits = "Kernel categories overlap. Swap rates describe VM pages, not physical disk throughput."
    }
    private struct PowerRecord: Encodable {
        let lowPowerMode: Bool
        let cpuSpeedLimitPercent: Int?
        let schedulerLimitPercent: Int?
        let fanRPMStatus = "unavailable-no-qualified-provider"
        let temperatureStatus = "unavailable-no-qualified-provider"
        let limits = "CPU allowances are OS limits, not clock measurements or proof of thermal cause."
    }

    public static func data(for snapshot: LiveSnapshot, physicalMemory: UInt64) throws -> Data {
        let processes = snapshot.processes.sorted { $0.id.pid < $1.id.pid }
        let aliases = Dictionary(processes.enumerated().map { ($0.element.id.pid, "process-\($0.offset + 1)") }, uniquingKeysWith: { first, _ in first })
        let byPID = Dictionary(processes.map { ($0.id.pid, $0) }, uniquingKeysWith: { first, _ in first })
        let records = processes.map { process in
            let parent = byPID[process.parent]
            return ProcessRecord(alias: aliases[process.id.pid]!,
                parentAlias: parent.map { $0.id.started <= process.id.started } == true ? aliases[process.parent] : nil,
                agent: process.agent, cpuPercent: finite(process.cpu), residentBytes: process.memory,
                ports: process.ports.map { PortRecord(number: $0.port, transport: $0.transport == "TCP" ? "TCP" : "UDP", scope: $0.loopback ? "loopback" : "non-loopback") },
                portsIncomplete: process.portsIncomplete)
        }
        let document = Document(capturedAt: snapshot.date, socketSampleAt: snapshot.portsDate,
            physicalMemoryBytes: physicalMemory, memoryHeadroomRatio: finite(snapshot.system.memoryHeadroomRatio),
            systemCPUCores: finite(snapshot.system.usedCPUCores), pressure: snapshot.pressure,
            swapBytes: snapshot.system.swapUsedBytes, compressedBytes: snapshot.compressed,
            memoryEvidence: snapshot.system.memory.map { MemoryRecord(freeBytes: $0.freeBytes,
                inactiveBytes: $0.inactiveBytes, wiredBytes: $0.wiredBytes, fileBackedBytes: $0.fileBackedBytes,
                compressedBytes: $0.compressedBytes, swapInBytesPerSecond: finite($0.swapInBytesPerSecond),
                swapOutBytesPerSecond: finite($0.swapOutBytesPerSecond), rateIntervalSeconds: finite($0.rateIntervalSeconds)) },
            powerEvidence: snapshot.system.power.map { PowerRecord(lowPowerMode: $0.lowPowerMode,
                cpuSpeedLimitPercent: $0.cpuSpeedLimitPercent, schedulerLimitPercent: $0.schedulerLimitPercent) },
            thermal: snapshot.system.thermal, scanSeconds: finite(snapshot.scanSeconds),
            unavailableProcesses: snapshot.unavailableProcesses, processes: records)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(document)
    }

    private static func finite(_ value: Double?) -> Double? { value.flatMap { $0.isFinite ? $0 : nil } }
}
