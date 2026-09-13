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

extension WidgetSnapshotStoreTests {
    /// 0.7.0-beta.1 shipped an unprefixed App Group id the macOS sandbox
    /// ignores, leaving a container behind with a snapshot nothing reads.
    func testLegacySnapshotIsRemoved() throws {
        let legacy = containerURL.appendingPathComponent(WidgetSharing.snapshotFilename)
        try Data("{}".utf8).write(to: legacy)
        WidgetSnapshotStore.removeLegacySnapshots { _ in self.containerURL }
        XCTAssertFalse(FileManager.default.fileExists(atPath: legacy.path))
    }

    /// The container may already be gone, or never have existed on a machine
    /// that only ever ran the fixed build.
    func testCleanupIsSilentWhenNothingIsThere() {
        WidgetSnapshotStore.removeLegacySnapshots { _ in self.containerURL }
        WidgetSnapshotStore.removeLegacySnapshots { _ in nil }
    }

    /// Only the snapshot file is ours to delete — the directory itself may
    /// hold data this app never wrote.
    func testCleanupLeavesTheContainerDirectoryAlone() throws {
        let other = containerURL.appendingPathComponent("someone-elses.json")
        try Data("{}".utf8).write(to: other)
        try Data("{}".utf8).write(
            to: containerURL.appendingPathComponent(WidgetSharing.snapshotFilename))
        WidgetSnapshotStore.removeLegacySnapshots { _ in self.containerURL }
        XCTAssertTrue(FileManager.default.fileExists(atPath: other.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: containerURL.path))
    }

    /// The prefixed id is what the macOS sandbox can verify against the
    /// signing team; reverting it silently breaks the widget.
    func testAppGroupIDCarriesTheTeamPrefix() {
        XCTAssertTrue(WidgetSharing.appGroupID.hasPrefix("7S3F9767BM."),
                      "an unprefixed group id is ignored by the sandbox")
    }
}
