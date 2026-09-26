import Foundation
@testable import PerformanceCore
import XCTest

final class AppAccessReviewStoreTests: XCTestCase {
    func testNotesPersistWithStatusAndDate() async throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
            .appendingPathComponent("review.json")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let checkedAt = Date(timeIntervalSince1970: 1_700_000_000)
        let store = AppAccessReviewStore(fileURL: url)
        let allowed = try await store.record(appPath: "/Applications/Example.app", bundleID: "example.app",
                                             area: "Full Disk Access", status: .shownAllowed, at: checkedAt)
        XCTAssertEqual(allowed.count, 1)
        XCTAssertEqual(allowed[0].checkedAt, checkedAt)
        XCTAssertEqual(allowed[0].status, .shownAllowed)

        let reloaded = await AppAccessReviewStore(fileURL: url).load()
        XCTAssertEqual(reloaded, allowed)
        let replaced = try await store.record(appPath: "/Applications/Example.app", bundleID: "example.app",
                                              area: "Full Disk Access", status: .shownOff)
        XCTAssertEqual(replaced.count, 1)
        XCTAssertEqual(replaced[0].status, .shownOff)
        let removed = try await store.remove(appPath: "/Applications/Example.app", area: "Full Disk Access")
        XCTAssertEqual(removed, [])
    }

    func testRejectsUnknownAreaAndKeepsPreviousNotes() async throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
            .appendingPathComponent("review.json")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let store = AppAccessReviewStore(fileURL: url)
        _ = try await store.record(appPath: "/Applications/Example.app", bundleID: nil,
                                   area: "Login Items", status: .notListed)
        do {
            _ = try await store.record(appPath: "/Applications/Example.app", bundleID: nil,
                                       area: "Unknown", status: .shownAllowed)
            XCTFail("Unknown categories must be rejected")
        } catch { }
        let notes = await store.load()
        XCTAssertEqual(notes.count, 1)
        XCTAssertEqual(notes[0].status, .notListed)
    }
}
