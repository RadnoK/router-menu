import XCTest
@testable import ZteMenu

final class ModemDataTests: XCTestCase {
    // Fixture: realna odpowiedź modemu (patrz modem-api-findings.md)
    private let raw: [String: String] = [
        "network_type": "ENDC",
        "signalbar": "5",
        "battery_value": "60",
        "battery_charging": "0",
        "ppp_status": "ppp_connected",
        "network_provider": "T-Mobile.pl",
        "Z5g_rsrp": "-81",
        "Z5g_SINR": "33.0",
    ]

    func testParsesBattery() {
        let d = ModemData.parse(raw)
        XCTAssertEqual(d.batteryPercent, 60)
        XCTAssertFalse(d.isCharging)
    }

    func testParsesSignal() {
        let d = ModemData.parse(raw)
        XCTAssertEqual(d.signalBars, 5)
        XCTAssertEqual(d.rsrp, -81)
        XCTAssertEqual(d.sinr, 33.0)
    }

    func testParsesNetworkAndProvider() {
        let d = ModemData.parse(raw)
        XCTAssertEqual(d.networkType, "ENDC")
        XCTAssertEqual(d.networkLabel, "5G")
        XCTAssertEqual(d.provider, "T-Mobile.pl")
        XCTAssertTrue(d.isOnline)
    }

    func testEmptyStringsBecomeNil() {
        let d = ModemData.parse([
            "signalbar": "3",
            "battery_value": "",
            "Z5g_rsrp": "",
            "Z5g_SINR": "",
            "network_type": "LTE",
            "ppp_status": "ppp_disconnected",
        ])
        XCTAssertNil(d.batteryPercent)
        XCTAssertNil(d.rsrp)
        XCTAssertNil(d.sinr)
        XCTAssertEqual(d.signalBars, 3)
        XCTAssertFalse(d.isOnline)
    }

    func testChargingFlag() {
        var r = raw; r["battery_charging"] = "1"
        XCTAssertTrue(ModemData.parse(r).isCharging)
    }

    func testUnknownNetworkTypeFallsBackToRaw() {
        var r = raw; r["network_type"] = "WCDMA"
        XCTAssertEqual(ModemData.parse(r).networkLabel, "WCDMA")
    }

    func testSignalDescription() {
        var r = raw; r["signalbar"] = "5"
        XCTAssertEqual(ModemData.parse(r).signalDescription, "Bardzo dobry")
        r["signalbar"] = "0"
        XCTAssertEqual(ModemData.parse(r).signalDescription, "Brak")
    }
}
