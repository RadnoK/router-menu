import XCTest
@testable import RouterMenu

final class WidgetSnapshotStoreTests: XCTestCase {
    private var containerURL: URL!

    override func setUpWithError() throws {
        containerURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("widget-store-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: containerURL, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: containerURL)
    }

    private func make(battery: Int? = 80) -> WidgetSnapshot {
        WidgetSnapshot(capturedAt: Date(timeIntervalSince1970: 1_700_000_000),
                       deviceName: "ZTE", batteryPercent: battery, isCharging: true,
                       signalBars: 4, networkLabel: "5G", rsrp: -90, sinr: 10,
                       rxSpeed: 1, txSpeed: 2, sessionRx: 3, sessionTx: 4,
                       batteryHistory: [], isOnline: true)
    }

    func testWriteThenReadReturnsTheSnapshot() {
        let store = WidgetSnapshotStore(containerURL: containerURL)
        let snapshot = make()
        store.write(snapshot)
        XCTAssertEqual(store.read(), snapshot)
    }

    func testReadingBeforeAnyWriteReturnsNil() {
        XCTAssertNil(WidgetSnapshotStore(containerURL: containerURL).read())
    }

    func testWriteOverwritesThePreviousSnapshot() {
        let store = WidgetSnapshotStore(containerURL: containerURL)
        store.write(make(battery: 80))
        store.write(make(battery: 20))
        XCTAssertEqual(store.read()?.batteryPercent, 20)
    }

    func testClearRemovesTheSnapshot() {
        let store = WidgetSnapshotStore(containerURL: containerURL)
        store.write(make())
        store.clear()
        XCTAssertNil(store.read())
    }

    /// Ad-hoc-signed local builds have no App Group, so the container URL is
    /// nil. The app must keep working; the widget simply has nothing to show.
    func testMissingContainerDegradesToNoOp() {
        let store = WidgetSnapshotStore(containerURL: nil)
        XCTAssertFalse(store.isAvailable)
        store.write(make())
        XCTAssertNil(store.read())
        store.clear()
    }

    func testCorruptFileReadsAsNoDataRatherThanThrowing() throws {
        let store = WidgetSnapshotStore(containerURL: containerURL)
        try Data("not json".utf8).write(
            to: containerURL.appendingPathComponent(WidgetSharing.snapshotFilename))
        XCTAssertNil(store.read())
    }
}

extension WidgetSnapshotStoreTests {
    /// An unsandboxed process gets a Group Containers path back even when the
    /// directory was never created, so a URL alone does not mean the container
    /// is usable. Trusting it made every write vanish without an error.
    func testNonexistentContainerIsReportedUnavailable() {
        let missing = FileManager.default.temporaryDirectory
            .appendingPathComponent("never-created-\(UUID().uuidString)", isDirectory: true)
        let store = WidgetSnapshotStore(containerURL: missing)
        XCTAssertFalse(store.isAvailable)
        store.write(make())
        XCTAssertNil(store.read())
    }
}
