import XCTest
@testable import RouterMenu

@MainActor
final class HistoryStoreTests: XCTestCase {
    private func tempFile() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("hist-\(UUID().uuidString).json")
    }

    func testAddAndTrimTo24h() {
        var clock = Date(timeIntervalSince1970: 1_000_000)
        let store = HistoryStore(fileURL: tempFile(), now: { clock })

        store.add(battery: 80, totalRx: 800, totalTx: 200)
        clock = clock.addingTimeInterval(60)
        store.add(battery: 79, totalRx: 1600, totalTx: 400)
        // jump of 25h — the first sample falls out of the window
        clock = clock.addingTimeInterval(25 * 3600)
        store.add(battery: 70, totalRx: 2400, totalTx: 600)

        // only samples from the last 24h remain (the last one)
        XCTAssertEqual(store.samples.count, 1)
        XCTAssertEqual(store.samples.last?.batteryPercent, 70)
    }

    func testDownloadSpeedFromRxDeltas() {
        var clock = Date(timeIntervalSince1970: 2_000_000)
        let store = HistoryStore(fileURL: tempFile(), now: { clock })
        store.add(battery: 50, totalRx: 1000, totalTx: 9000)
        clock = clock.addingTimeInterval(10) // +10 s
        store.add(battery: 50, totalRx: 6000, totalTx: 9000) // +5000 rx bytes
        let series = store.downloadSpeedSeries()
        // 5000 bytes / 10 s = 500 B/s — rx only, tx must not leak in
        XCTAssertEqual(series.count, 1)
        XCTAssertEqual(series.last?.1 ?? 0, 500, accuracy: 0.1)
    }

    func testUploadSpeedFromTxDeltas() {
        var clock = Date(timeIntervalSince1970: 2_000_000)
        let store = HistoryStore(fileURL: tempFile(), now: { clock })
        store.add(battery: 50, totalRx: 9000, totalTx: 1000)
        clock = clock.addingTimeInterval(10)
        store.add(battery: 50, totalRx: 9000, totalTx: 3000) // +2000 tx bytes
        let series = store.uploadSpeedSeries()
        XCTAssertEqual(series.count, 1)
        XCTAssertEqual(series.last?.1 ?? 0, 200, accuracy: 0.1)
    }

    func testCounterResetProducesNoPointAndChainRestarts() {
        var clock = Date(timeIntervalSince1970: 2_000_000)
        let store = HistoryStore(fileURL: tempFile(), now: { clock })
        store.add(totalRx: 50_000, totalTx: 0)
        clock = clock.addingTimeInterval(10)
        // Router rebooted: the counter starts over — a naive diff would be a
        // huge negative (or, mixed with another device, a huge positive).
        store.add(totalRx: 100, totalTx: 0)
        clock = clock.addingTimeInterval(10)
        store.add(totalRx: 1100, totalTx: 0)

        let series = store.downloadSpeedSeries()
        XCTAssertEqual(series.count, 1, "the reset boundary must not become a data point")
        XCTAssertEqual(series.last?.1 ?? 0, 100, accuracy: 0.1)
    }

    func testLongGapProducesNoPoint() {
        var clock = Date(timeIntervalSince1970: 2_000_000)
        let store = HistoryStore(fileURL: tempFile(), now: { clock })
        store.add(totalRx: 1000, totalTx: 0)
        // The app was asleep for 2 h — averaging over that window would draw a
        // misleading plateau, so the pair is skipped.
        clock = clock.addingTimeInterval(2 * 3600)
        store.add(totalRx: 2_000_000, totalTx: 0)
        clock = clock.addingTimeInterval(60)
        store.add(totalRx: 2_060_000, totalTx: 0)

        let series = store.downloadSpeedSeries()
        XCTAssertEqual(series.count, 1)
        XCTAssertEqual(series.last?.1 ?? 0, 1000, accuracy: 0.1)
    }

    func testSignalSeries() {
        var clock = Date(timeIntervalSince1970: 2_000_000)
        let store = HistoryStore(fileURL: tempFile(), now: { clock })
        store.add(rsrp: -95, sinr: 12.5)
        clock = clock.addingTimeInterval(60)
        store.add(rsrp: -101, sinr: nil)

        XCTAssertEqual(store.rsrpSeries().map(\.1), [-95, -101])
        XCTAssertEqual(store.sinrSeries().map(\.1), [12.5])
    }

    func testLegacySamplesWithOnlyTotalBytesStillLoad() throws {
        let file = tempFile()
        let legacy = #"[{"id":"6F1E5A31-0000-0000-0000-000000000001","timestamp":746218000,"batteryPercent":64,"totalBytes":123456}]"#
        try Data(legacy.utf8).write(to: file)

        let store = HistoryStore(fileURL: file, now: { Date(timeIntervalSince1970: 746_218_060) })
        XCTAssertEqual(store.samples.count, 1)
        XCTAssertEqual(store.batterySeries().map(\.1), [64])
        // Legacy samples carry no rx/tx split, so they feed no speed series.
        XCTAssertTrue(store.downloadSpeedSeries().isEmpty)
    }

    func testPersistsToDisk() {
        let file = tempFile()
        let a = HistoryStore(fileURL: file, now: { Date(timeIntervalSince1970: 3_000_000) })
        a.add(battery: 42, totalRx: 60, totalTx: 40, rsrp: -88, sinr: 7)

        let b = HistoryStore(fileURL: file, now: { Date(timeIntervalSince1970: 3_000_060) })
        XCTAssertEqual(b.samples.first?.batteryPercent, 42)
        XCTAssertEqual(b.samples.first?.totalRx, 60)
        XCTAssertEqual(b.samples.first?.totalTx, 40)
        XCTAssertEqual(b.samples.first?.rsrp, -88)
        XCTAssertEqual(b.samples.first?.sinr, 7)
    }
}
