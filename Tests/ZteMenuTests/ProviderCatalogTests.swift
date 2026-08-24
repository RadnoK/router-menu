import XCTest
@testable import ZteMenu

/// Every provider the enum names must be fully described — these are the
/// compile-time-adjacent guarantees the architecture's "one folder + one
/// case" promise rests on.
final class ProviderCatalogTests: XCTestCase {
    func testEveryProviderHasACoherentDescriptor() {
        for kind in ProviderKind.allCases {
            let d = ProviderCatalog.descriptor(for: kind)
            XCTAssertFalse(d.displayName.isEmpty, "\(kind) has no display name")
            XCTAssertFalse(d.supportedMatchModes.isEmpty, "\(kind) supports no match mode")
            XCTAssertTrue(d.supportedMatchModes.contains(d.defaultMatchMode),
                          "\(kind)'s default match mode is not among its supported modes")
            if d.defaultMatchMode == .ssid {
                XCTAssertFalse(d.defaultSSID.isEmpty,
                               "\(kind) matches by SSID by default but ships no default SSID")
            }
        }
    }

    func testZTEDescriptorMatchesTheU50() {
        let d = ProviderCatalog.descriptor(for: .zte)
        XCTAssertEqual(d.displayName, "ZTE")
        XCTAssertEqual(d.defaultBaseURL.absoluteString, "http://192.168.0.1")
        XCTAssertEqual(d.defaultSSID, "ZTE_B4B622")
        XCTAssertEqual(d.supportedMatchModes, [.ssid, .ipProbe])
        XCTAssertEqual(d.defaultMatchMode, .ssid)
        XCTAssertTrue(d.capabilities.hasBattery)
        XCTAssertEqual(d.capabilities.passwordRole, .unlocksTraffic)
        XCTAssertFalse(d.capabilities.needsUsername)
        XCTAssertTrue(d.capabilities.hasRadioSignal)
    }

    func testZTEFactoryBuildsAZTEDriverFromAProfile() {
        var profile = ModemProfile.makeDefault(provider: .zte)
        profile.modemIP = "10.0.0.1"
        let d = ProviderCatalog.descriptor(for: .zte)
        let driver = d.makeDriver(profile, "secret", URLSession.shared)
        XCTAssertTrue(driver is ZTEClient)
    }

    func testMatchModeRawValuesAreStable() {
        // Persisted in profiles — renaming a case is a settings migration.
        XCTAssertEqual(MatchMode.ssid.rawValue, "ssid")
        XCTAssertEqual(MatchMode.ipProbe.rawValue, "ipProbe")
    }

    func testAsusDescriptorMatchesAsuswrt() {
        let d = ProviderCatalog.descriptor(for: .asus)
        XCTAssertEqual(d.displayName, "Asus")
        XCTAssertEqual(d.defaultBaseURL.absoluteString, "http://192.168.50.1")
        XCTAssertEqual(d.defaultSSID, "", "no factory SSID exists for user-named networks")
        XCTAssertEqual(d.supportedMatchModes, [.ssid, .ipProbe])
        XCTAssertEqual(d.defaultMatchMode, .ipProbe)
        XCTAssertFalse(d.capabilities.hasBattery)
        XCTAssertEqual(d.capabilities.passwordRole, .requiredForAll)
        XCTAssertTrue(d.capabilities.needsUsername)
        XCTAssertFalse(d.capabilities.hasRadioSignal)
    }

    func testAsusFactoryBuildsAnAsusDriverFromAProfile() {
        let profile = ModemProfile.makeDefault(provider: .asus)
        XCTAssertEqual(profile.modemIP, "192.168.50.1")
        XCTAssertEqual(profile.matchMode, .ipProbe)
        let driver = ProviderCatalog.descriptor(for: .asus)
            .makeDriver(profile, "haslo", URLSession.shared)
        XCTAssertTrue(driver is AsusClient)
    }

    func testProviderRawValuesAreStable() {
        XCTAssertEqual(ProviderKind.zte.rawValue, "zte")
        XCTAssertEqual(ProviderKind.asus.rawValue, "asus")
    }
}
