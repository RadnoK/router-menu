import XCTest
@testable import ZteMenu

final class ModemProfileTests: XCTestCase {
    func testMakeDefaultPrefillsFromTheDescriptor() {
        let p = ModemProfile.makeDefault(provider: .zte)
        XCTAssertEqual(p.provider, .zte)
        XCTAssertEqual(p.matchMode, .ssid)
        XCTAssertEqual(p.ssid, "ZTE_B4B622")
        XCTAssertEqual(p.modemIP, "192.168.0.1")
        XCTAssertFalse(p.showBatteryPercent)
        XCTAssertEqual(p.batteryNotifications, BatteryNotificationSettings())
        XCTAssertEqual(p.stats, StatVisibility())
    }

    func testBaseURLDerivesFromTheIP() {
        var p = ModemProfile.makeDefault(provider: .zte)
        p.modemIP = "10.0.0.138"
        XCTAssertEqual(p.baseURL.absoluteString, "http://10.0.0.138")
    }

    func testUnparsableIPFallsBackToTheProviderDefault() {
        var p = ModemProfile.makeDefault(provider: .zte)
        p.modemIP = "not a host"
        XCTAssertEqual(p.baseURL.absoluteString, "http://192.168.0.1")
    }

    func testRoundTripsThroughCodable() throws {
        var p = ModemProfile.makeDefault(provider: .zte)
        p.matchMode = .ipProbe
        p.showBatteryPercent = true
        p.batteryNotifications.addThreshold(percent: 35, isUrgent: true)
        let decoded = try JSONDecoder().decode(ModemProfile.self,
                                               from: try JSONEncoder().encode(p))
        XCTAssertEqual(decoded, p)
        XCTAssertEqual(decoded.id, p.id, "identity must survive persistence")
    }

    func testDecodesAnEmptyObjectToUsableDefaults() throws {
        // Forgiving decode, the house style: a future field addition must not
        // reset the user's whole configuration.
        let p = try JSONDecoder().decode(ModemProfile.self, from: Data("{}".utf8))
        XCTAssertEqual(p.provider, .zte)
        XCTAssertEqual(p.matchMode, .ssid)
    }
}
