import Foundation
@testable import PerformanceCore
import XCTest

final class SnapshotExportTests: XCTestCase {
    func testExportRedactsIdentityWhileRetainingMeasurementsAndAncestry() throws {
        let data = try SnapshotExport.data(for: snapshot(), physicalMemory: 48_000_000_000)
        let text = String(decoding: data, as: UTF8.self)
        for privateValue in ["/Users/secret-owner", "private-client", "192.168.7.33", "987654", "987655", "custom-sensitive-name"] {
            XCTAssertFalse(text.contains(privateValue), privateValue)
        }
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(json["schema"] as? String, "performancedaddy.snapshot.v1")
        let rows = try XCTUnwrap(json["processes"] as? [[String: Any]])
        XCTAssertEqual(rows.count, 2)
        XCTAssertEqual(rows[0]["agent"] as? String, "Devin")
        XCTAssertEqual(rows[1]["parentAlias"] as? String, rows[0]["alias"] as? String)
        XCTAssertEqual(rows[0]["cpuPercent"] as? Double, 25)
        XCTAssertEqual(rows[0]["residentBytes"] as? Int, 1024)
        XCTAssertEqual(rows[0]["physicalFootprintBytes"] as? Int, 768)
        XCTAssertEqual(rows[0]["cumulativeDiskReadBytes"] as? Int, 4_096)
        XCTAssertEqual(rows[0]["cumulativeDiskWrittenBytes"] as? Int, 2_048)
        XCTAssertEqual((rows[0]["ports"] as? [[String: Any]])?.first?["number"] as? Int, 3000)
    }

    func testUnknownAndNonFiniteMeasurementsAreNotExportedAsZero() throws {
        let data = try SnapshotExport.data(for: snapshot(cpu: .nan), physicalMemory: 48_000_000_000)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let rows = try XCTUnwrap(json["processes"] as? [[String: Any]])
        XCTAssertNil(rows[0]["cpuPercent"])
        XCTAssertNil(rows[1]["physicalFootprintBytes"])
        XCTAssertNil(rows[1]["cumulativeDiskReadBytes"])
        XCTAssertNil(rows[1]["cumulativeDiskWrittenBytes"])
        XCTAssertNil(json["swapBytes"])
        XCTAssertEqual(json["unavailableProcesses"] as? Int, 3)
        XCTAssertEqual(rows[0]["portsIncomplete"] as? Bool, true)
        XCTAssertNil(json["memoryEvidence"])
        XCTAssertNil(json["powerEvidence"])
    }

    func testResourceEvidenceExportKeepsUnknownSensorsExplicit() throws {
        let memory = MemoryEvidence(freeBytes: 1, inactiveBytes: 2, wiredBytes: 3,
            fileBackedBytes: 4, compressedBytes: 5, swapInBytesPerSecond: .nan,
            swapOutBytesPerSecond: 8192, rateIntervalSeconds: 2)
        let power = PowerEvidence(lowPowerMode: true, cpuSpeedLimitPercent: nil, schedulerLimitPercent: 80)
        let data = try SnapshotExport.data(for: snapshot(memory: memory, power: power), physicalMemory: 100)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let vm = try XCTUnwrap(json["memoryEvidence"] as? [String: Any])
        XCTAssertEqual(vm["wiredBytes"] as? Int, 3)
        XCTAssertNil(vm["swapInBytesPerSecond"])
        XCTAssertEqual(vm["swapOutBytesPerSecond"] as? Double, 8192)
        XCTAssertEqual(vm["rateIntervalSeconds"] as? Double, 2)
        let limits = try XCTUnwrap(json["powerEvidence"] as? [String: Any])
        XCTAssertEqual(limits["lowPowerMode"] as? Bool, true)
        XCTAssertNil(limits["cpuSpeedLimitPercent"])
        XCTAssertEqual(limits["schedulerLimitPercent"] as? Int, 80)
        XCTAssertEqual(limits["fanRPMStatus"] as? String, "unavailable-no-qualified-provider")
        XCTAssertEqual(limits["temperatureStatus"] as? String, "unavailable-no-qualified-provider")
    }

    private func snapshot(cpu: Double = 25, memory: MemoryEvidence? = nil, power: PowerEvidence? = nil) -> LiveSnapshot {
        let date = Date(timeIntervalSince1970: 1_000)
        let parent = LiveProcess(id: .init(pid: 987654, started: 10), parent: 1, uid: 501,
            name: "custom-sensitive-name", executable: "/Users/secret-owner/bin/devin",
            directory: "/Users/secret-owner/private-client", cpu: cpu, memory: 1024,
            ports: [.init(port: 3000, transport: "TCP", address: "192.168.7.33", loopback: false)], portsIncomplete: true,
            footprint: 768, diskReadBytes: 4_096, diskWrittenBytes: 2_048)
        let child = LiveProcess(id: .init(pid: 987655, started: 11), parent: 987654, uid: 501,
            name: "custom-sensitive-name", executable: "/bin/node", directory: "/Users/secret-owner/private-client",
            cpu: nil, memory: 512)
        return LiveSnapshot(date: date, processes: [child, parent],
            system: SystemSample(timestamp: date, usedCPUCores: 1, memoryHeadroomRatio: 0.5,
                                 swapUsedBytes: nil, diskFreeBytes: nil, thermal: .nominal, processes: [], memory: memory, power: power),
            pressure: "Normal", compressed: nil, unavailableProcesses: 3, portsDate: date, scanSeconds: 0.03)
    }
}
