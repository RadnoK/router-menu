import XCTest
@testable import ZteMenu

final class ZTEClientParseTests: XCTestCase {
    // Fixture: a real modem response (see modem-api-findings.md)
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
        let d = ZTEClient.parse(raw)
        XCTAssertEqual(d.batteryPercent, 60)
        XCTAssertFalse(d.isCharging)
    }

    func testParsesSignal() {
        let d = ZTEClient.parse(raw)
        XCTAssertEqual(d.signalBars, 5)
        XCTAssertEqual(d.rsrp, -81)
        XCTAssertEqual(d.sinr, 33.0)
    }

    func testParsesNetworkAndProvider() {
        let d = ZTEClient.parse(raw)
        XCTAssertEqual(d.networkType, "ENDC")
        XCTAssertEqual(d.networkLabel, "5G")
        XCTAssertEqual(d.provider, "T-Mobile.pl")
        XCTAssertTrue(d.isOnline)
    }

    func testEmptyStringsBecomeNil() {
        let d = ZTEClient.parse([
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
        XCTAssertTrue(ZTEClient.parse(r).isCharging)
    }

    func testUnknownNetworkTypeFallsBackToRaw() {
        var r = raw; r["network_type"] = "WCDMA"
        XCTAssertEqual(ZTEClient.parse(r).networkLabel, "WCDMA")
    }

    func testSignalQuality() {
        var r = raw; r["signalbar"] = "5"
        XCTAssertEqual(ZTEClient.parse(r).signalQuality, .veryGood)
        r["signalbar"] = "0"
        XCTAssertEqual(ZTEClient.parse(r).signalQuality, .noSignal)
        r["signalbar"] = "3"
        XCTAssertEqual(ZTEClient.parse(r).signalQuality, .medium)
    }

    func testParsesTransferFields() {
        let d = ZTEClient.parse([
            "signalbar": "5", "network_type": "ENDC", "ppp_status": "ppp_connected",
            "realtime_rx_thrpt": "6149", "realtime_tx_thrpt": "60709",
            "realtime_rx_bytes": "1008395299", "realtime_tx_bytes": "1850536546",
            "total_rx_bytes": "111604507190", "total_tx_bytes": "22997555141",
            "monthly_rx_bytes": "20248857403", "monthly_tx_bytes": "3998344877",
            "realtime_time": "7100", "monthly_time": "127070",
        ])
        XCTAssertEqual(d.rxSpeed, 6149)
        XCTAssertEqual(d.txSpeed, 60709)
        XCTAssertEqual(d.sessionRx, 1008395299)
        XCTAssertEqual(d.totalRx, 111604507190)
        XCTAssertEqual(d.monthlyTx, 3998344877)
        XCTAssertEqual(d.sessionUptime, 7100)
        XCTAssertEqual(d.monthlyUptime, 127070)
        XCTAssertEqual(d.totalBytesForHistory, 111604507190 + 22997555141)
    }

    func testTransferFieldsNilWhenAbsent() {
        let d = ZTEClient.parse(["signalbar": "3", "network_type": "LTE"])
        XCTAssertNil(d.rxSpeed)
        XCTAssertNil(d.totalRx)
        XCTAssertNil(d.totalBytesForHistory)
    }
}
