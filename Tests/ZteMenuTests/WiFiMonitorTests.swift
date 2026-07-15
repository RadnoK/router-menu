import XCTest
@testable import ZteMenu

private struct FixedSSID: SSIDReading {
    let value: String?
    func currentSSID() -> String? { value }
}

final class WiFiMonitorTests: XCTestCase {
    func testOnTargetNetwork() {
        let m = WiFiMonitor(targetSSID: "ZTE_B4B622", reader: FixedSSID(value: "ZTE_B4B622"))
        XCTAssertTrue(m.isOnTargetNetwork)
    }

    func testDifferentNetwork() {
        let m = WiFiMonitor(targetSSID: "ZTE_B4B622", reader: FixedSSID(value: "Dom_5G"))
        XCTAssertFalse(m.isOnTargetNetwork)
    }

    func testNoWiFi() {
        let m = WiFiMonitor(targetSSID: "ZTE_B4B622", reader: FixedSSID(value: nil))
        XCTAssertFalse(m.isOnTargetNetwork)
    }
}
