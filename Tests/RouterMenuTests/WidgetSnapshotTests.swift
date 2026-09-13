import XCTest
@testable import RouterMenu

final class WidgetSnapshotTests: XCTestCase {
    private func make(capturedAt: Date = Date(timeIntervalSince1970: 1_700_000_000),
                      battery: Int? = 80,
                      history: [WidgetSnapshot.Point] = []) -> WidgetSnapshot {
        WidgetSnapshot(capturedAt: capturedAt,
                       deviceName: "ZTE",
                       batteryPercent: battery,
                       isCharging: false,
                       signalBars: 3,
                       networkLabel: "5G",
                       rsrp: -95,
                       sinr: 12.5,
                       rxSpeed: 1024,
                       txSpeed: 512,
                       sessionRx: 4096,
                       sessionTx: 2048,
                       batteryHistory: history,
                       isOnline: true)
    }

    private func roundTrip(_ snapshot: WidgetSnapshot) throws -> WidgetSnapshot {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(WidgetSnapshot.self, from: encoder.encode(snapshot))
    }

    func testRoundTripPreservesEveryField() throws {
        let original = make(history: [.init(t: Date(timeIntervalSince1970: 1), v: 50)])
        XCTAssertEqual(try roundTrip(original), original)
    }

    func testNilBatterySurvivesRoundTrip() throws {
        XCTAssertNil(try roundTrip(make(battery: nil)).batteryPercent)
    }

    /// The widget host keeps running the old binary after an app update, so a
    /// payload missing fields it has never heard of must still decode.
    func testDecodesPayloadFromAnOlderWriter() throws {
        let json = Data(#"{"capturedAt":"2023-11-14T22:13:20Z","deviceName":"ZTE"}"#.utf8)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let snapshot = try decoder.decode(WidgetSnapshot.self, from: json)
        XCTAssertEqual(snapshot.deviceName, "ZTE")
        XCTAssertNil(snapshot.batteryPercent)
        XCTAssertEqual(snapshot.signalBars, 0)
        XCTAssertEqual(snapshot.networkLabel, "—")
        XCTAssertTrue(snapshot.batteryHistory.isEmpty)
    }

    /// Unknown keys from a newer writer must be ignored, not fatal.
    func testDecodesPayloadFromANewerWriter() throws {
        let json = Data(#"{"capturedAt":"2023-11-14T22:13:20Z","deviceName":"ZTE","futureField":42}"#.utf8)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        XCTAssertEqual(try decoder.decode(WidgetSnapshot.self, from: json).deviceName, "ZTE")
    }
}
