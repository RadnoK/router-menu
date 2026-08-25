import XCTest
@testable import RouterMenu

final class StatVisibilityTests: XCTestCase {
    func testDefaultsAreAllOn() {
        let v = StatVisibility()
        XCTAssertTrue(v.basic && v.radio && v.transfer && v.uptime)
        XCTAssertTrue(v.session && v.transferChart && v.signalChart && v.batteryChart)
        XCTAssertTrue(v.localIP)
    }

    func testLegacyPayloadWithoutChartKeysDecodesToDefaults() throws {
        // A ≤0.5.x settings payload knows nothing about the chart toggles —
        // it must decode with them ON, not throw away the user's settings.
        let legacy = #"{"basic":false,"radio":true,"transfer":true,"uptime":false}"#
        let v = try JSONDecoder().decode(StatVisibility.self, from: Data(legacy.utf8))
        XCTAssertFalse(v.basic)
        XCTAssertFalse(v.uptime)
        XCTAssertTrue(v.session)
        XCTAssertTrue(v.transferChart)
        XCTAssertTrue(v.signalChart)
        XCTAssertTrue(v.batteryChart)
        XCTAssertTrue(v.localIP)
    }

    func testRoundTripPreservesEveryToggle() throws {
        var v = StatVisibility()
        v.radio = false
        v.session = false
        v.transferChart = false
        let decoded = try JSONDecoder().decode(StatVisibility.self,
                                               from: JSONEncoder().encode(v))
        XCTAssertEqual(decoded, v)
    }
}
