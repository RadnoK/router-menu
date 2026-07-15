import XCTest
@testable import ZteMenu

@MainActor
final class HistoryStoreTests: XCTestCase {
    private func tempFile() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("hist-\(UUID().uuidString).json")
    }

    func testAddAndTrimTo24h() {
        var clock = Date(timeIntervalSince1970: 1_000_000)
        let store = HistoryStore(fileURL: tempFile(), now: { clock })

        store.add(battery: 80, totalBytes: 1000)
        clock = clock.addingTimeInterval(60)
        store.add(battery: 79, totalBytes: 2000)
        // skok o 25h — pierwsza próbka wypada
        clock = clock.addingTimeInterval(25 * 3600)
        store.add(battery: 70, totalBytes: 3000)

        // pozostają tylko próbki z ostatnich 24h (ostatnia)
        XCTAssertEqual(store.samples.count, 1)
        XCTAssertEqual(store.samples.last?.batteryPercent, 70)
    }

    func testDownloadSpeedFromDeltas() {
        var clock = Date(timeIntervalSince1970: 2_000_000)
        let store = HistoryStore(fileURL: tempFile(), now: { clock })
        store.add(battery: 50, totalBytes: 1000)
        clock = clock.addingTimeInterval(10) // +10 s
        store.add(battery: 50, totalBytes: 6000) // +5000 bajtów
        let series = store.downloadSpeedSeries()
        // 5000 bajtów / 10 s = 500 B/s
        XCTAssertEqual(series.last?.1 ?? 0, 500, accuracy: 0.1)
    }

    func testPersistsToDisk() {
        let file = tempFile()
        let a = HistoryStore(fileURL: file, now: { Date(timeIntervalSince1970: 3_000_000) })
        a.add(battery: 42, totalBytes: 100)

        let b = HistoryStore(fileURL: file, now: { Date(timeIntervalSince1970: 3_000_060) })
        XCTAssertEqual(b.samples.first?.batteryPercent, 42)
    }
}
