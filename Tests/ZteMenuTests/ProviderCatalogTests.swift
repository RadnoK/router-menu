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
            XCTAssertFalse(d.defaultSSID.isEmpty, "\(kind) has no default SSID")
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
    }

    func testZTEFactoryBuildsAZTEDriver() {
        let d = ProviderCatalog.descriptor(for: .zte)
        let driver = d.makeDriver(URL(string: "http://10.0.0.1")!, "secret", URLSession.shared)
        XCTAssertTrue(driver is ZTEClient)
    }

    func testMatchModeRawValuesAreStable() {
        // Persisted in profiles — renaming a case is a settings migration.
        XCTAssertEqual(MatchMode.ssid.rawValue, "ssid")
        XCTAssertEqual(MatchMode.ipProbe.rawValue, "ipProbe")
    }
}
