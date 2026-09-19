import Darwin
import Foundation
import IOKit.pwr_mgt

/// Kernel VM categories overlap; these are observations, not slices of a pie.
public struct MemoryEvidence: Equatable, Sendable {
    public let freeBytes: UInt64
    public let inactiveBytes: UInt64
    public let wiredBytes: UInt64
    public let fileBackedBytes: UInt64
    public let compressedBytes: UInt64
    public let swapInBytesPerSecond: Double?
    public let swapOutBytesPerSecond: Double?
    public let rateIntervalSeconds: Double?
}

/// A missing read breaks continuity. Long gaps (pause/sleep), counter resets,
/// invalid clocks and page-size changes require a fresh pair of observations.
struct SwapRateTracker {
    struct Counter {
        let time: Double
        let pageSize: UInt64
        let incoming: UInt64
        let outgoing: UInt64
    }
    private var previous: Counter?
    mutating func update(_ current: Counter?) -> (incoming: Double, outgoing: Double, interval: Double)? {
        defer { previous = current }
        guard let current, let previous,
              current.time.isFinite, previous.time.isFinite,
              current.pageSize > 0, current.pageSize == previous.pageSize,
              current.incoming >= previous.incoming, current.outgoing >= previous.outgoing
        else { return nil }
        let interval = current.time - previous.time
        guard interval >= 0.1, interval <= 30 else { return nil }
        let incoming = Double(current.incoming - previous.incoming) * Double(current.pageSize) / interval
        let outgoing = Double(current.outgoing - previous.outgoing) * Double(current.pageSize) / interval
        guard incoming.isFinite, outgoing.isFinite else { return nil }
        return (incoming, outgoing, interval)
    }
}

struct MemoryEvidenceReader {
    private var rates = SwapRateTracker()
    private let origin = ContinuousClock.now

    mutating func read() -> MemoryEvidence? {
        var vm = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.stride / MemoryLayout<integer_t>.stride)
        let result = withUnsafeMutablePointer(to: &vm) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        var page: vm_size_t = 0
        guard result == KERN_SUCCESS,
              host_page_size(mach_host_self(), &page) == KERN_SUCCESS, page > 0 else {
            _ = rates.update(nil)
            return nil
        }
        let elapsed = origin.duration(to: .now).components
        let seconds = Double(elapsed.seconds) + Double(elapsed.attoseconds) / 1e18
        let rate = rates.update(.init(time: seconds,
                                     pageSize: UInt64(page), incoming: vm.swapins, outgoing: vm.swapouts))
        return MemoryEvidence(freeBytes: UInt64(vm.free_count) * UInt64(page),
                              inactiveBytes: UInt64(vm.inactive_count) * UInt64(page),
                              wiredBytes: UInt64(vm.wire_count) * UInt64(page),
                              fileBackedBytes: UInt64(vm.external_page_count) * UInt64(page),
                              compressedBytes: UInt64(vm.compressor_page_count) * UInt64(page),
                              swapInBytesPerSecond: rate?.incoming, swapOutBytesPerSecond: rate?.outgoing,
                              rateIntervalSeconds: rate?.interval)
    }
}

public struct PowerEvidence: Equatable, Sendable {
    public let lowPowerMode: Bool
    public let cpuSpeedLimitPercent: Int?
    public let schedulerLimitPercent: Int?

    static func percentage(_ value: Any?) -> Int? {
        guard let number = value as? NSNumber,
              CFGetTypeID(number) != CFBooleanGetTypeID() else { return nil }
        let value = number.doubleValue
        guard value.isFinite, value >= 0, value <= 100, value.rounded() == value else { return nil }
        return Int(value)
    }

    static func read() -> PowerEvidence {
        var dictionary: Unmanaged<CFDictionary>?
        let result = IOPMCopyCPUPowerStatus(&dictionary)
        let values = dictionary?.takeRetainedValue() as? [String: Any]
        return PowerEvidence(lowPowerMode: ProcessInfo.processInfo.isLowPowerModeEnabled,
                             cpuSpeedLimitPercent: result == kIOReturnSuccess ? percentage(values?[kIOPMCPUPowerLimitProcessorSpeedKey]) : nil,
                             schedulerLimitPercent: result == kIOReturnSuccess ? percentage(values?[kIOPMCPUPowerLimitSchedulerTimeKey]) : nil)
    }
}
