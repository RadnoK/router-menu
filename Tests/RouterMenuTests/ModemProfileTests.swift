import XCTest
@testable import RouterMenu

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

    func testAdoptingAProviderKeepsTypedValues() {
        var p = ModemProfile.makeDefault(provider: .zte)
        p.ssid = "MyNetwork"
        p.modemIP = "10.0.0.7"
        p.matchMode = .ipProbe
        let adopted = p.adopting(provider: .zte)
        XCTAssertEqual(adopted.ssid, "MyNetwork")
        XCTAssertEqual(adopted.modemIP, "10.0.0.7")
        XCTAssertEqual(adopted.matchMode, .ipProbe,
                       "a supported mode survives the switch")
        XCTAssertEqual(adopted.id, p.id, "adopting a provider is not a new device")
    }

    func testAdoptingAProviderPrefillsEmptyFields() {
        var p = ModemProfile.makeDefault(provider: .zte)
        p.ssid = ""
        p.modemIP = ""
        let adopted = p.adopting(provider: .zte)
        XCTAssertEqual(adopted.ssid, "ZTE_B4B622")
        XCTAssertEqual(adopted.modemIP, "192.168.0.1")
    }

    func testNameAndUsernameDefaults() {
        let p = ModemProfile.makeDefault(provider: .zte)
        XCTAssertEqual(p.name, "", "no custom name until the user types one")
        XCTAssertEqual(p.username, "admin")
    }

    func testNameAndUsernameSurviveCodableAndAdopting() throws {
        var p = ModemProfile.makeDefault(provider: .zte)
        p.name = "Modem w plecaku"
        p.username = "root"
        let decoded = try JSONDecoder().decode(ModemProfile.self,
                                               from: try JSONEncoder().encode(p))
        XCTAssertEqual(decoded.name, "Modem w plecaku")
        XCTAssertEqual(decoded.username, "root")
        let adopted = p.adopting(provider: .zte)
        XCTAssertEqual(adopted.name, "Modem w plecaku", "a name belongs to the user, not the brand")
        XCTAssertEqual(adopted.username, "root")
    }

    func testLegacyPayloadWithoutNewFieldsDecodesToDefaults() throws {
        let p = try JSONDecoder().decode(ModemProfile.self, from: Data("{}".utf8))
        XCTAssertEqual(p.name, "")
        XCTAssertEqual(p.username, "admin")
    }
}
