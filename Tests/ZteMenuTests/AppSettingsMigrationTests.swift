import XCTest
@testable import ZteMenu

@MainActor
final class AppSettingsMigrationTests: XCTestCase {
    private func freshDefaults() -> UserDefaults {
        UserDefaults(suiteName: "mig-\(UUID().uuidString)")!
    }

    /// The exact shape a 0.4.x install has on disk.
    private let legacyPayload = #"""
    {"networkMode":"byIPReachable","ssid":"MyZTE","modemIP":"10.0.0.1",
     "refreshInterval":30,
     "stats":{"basic":false,"radio":true,"transfer":true,"uptime":true},
     "language":"pl","showBatteryPercent":true,"showWhenDisconnected":true,
     "batteryNotifications":{"thresholds":[{"id":"11111111-1111-1111-1111-111111111111",
       "percent":35,"isUrgent":true,"isEnabled":true}],"fullEnabled":true}}
    """#

    func testLegacyFlatPayloadBecomesOneZTEProfile() {
        let d = freshDefaults()
        d.set(Data(legacyPayload.utf8), forKey: "zte.settings")

        let s = SettingsStore(defaults: d).settings

        XCTAssertEqual(s.profiles.count, 1)
        let p = s.profiles[0]
        XCTAssertEqual(p.provider, .zte)
        XCTAssertEqual(p.matchMode, .ipProbe, "legacy byIPReachable maps to ipProbe")
        XCTAssertEqual(p.ssid, "MyZTE")
        XCTAssertEqual(p.modemIP, "10.0.0.1")
        XCTAssertTrue(p.showBatteryPercent)
        XCTAssertFalse(p.stats.basic)
        XCTAssertEqual(p.batteryNotifications.thresholds.map(\.percent), [35])
        XCTAssertTrue(p.batteryNotifications.fullEnabled)
        // App-scoped values stay app-scoped.
        XCTAssertEqual(s.refreshInterval, 30)
        XCTAssertEqual(s.language, .pl)
        XCTAssertTrue(s.showWhenDisconnected)
    }

    func testLegacyBySSIDMapsToSSIDMode() {
        let d = freshDefaults()
        d.set(Data(#"{"networkMode":"bySSID","ssid":"X"}"#.utf8), forKey: "zte.settings")
        XCTAssertEqual(SettingsStore(defaults: d).settings.profiles[0].matchMode, .ssid)
    }

    func testEmptyProfilesArrayIsRepaired() {
        let d = freshDefaults()
        d.set(Data(#"{"profiles":[]}"#.utf8), forKey: "zte.settings")
        let s = SettingsStore(defaults: d).settings
        XCTAssertEqual(s.profiles.count, 1, "the never-empty invariant holds")
        XCTAssertEqual(s.profiles[0].provider, .zte)
    }

    func testEncodingWritesOnlyTheNewSchema() throws {
        let data = try JSONEncoder().encode(AppSettings())
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertNotNil(object["profiles"])
        for legacyKey in ["networkMode", "ssid", "modemIP", "stats",
                          "showBatteryPercent", "batteryNotifications"] {
            XCTAssertNil(object[legacyKey], "legacy key \(legacyKey) must not be written back")
        }
    }

    func testMigratedProfileIdIsStableAcrossLaunches() {
        let d = freshDefaults()
        d.set(Data(legacyPayload.utf8), forKey: "zte.settings")
        let first = SettingsStore(defaults: d).settings.profiles[0].id
        let second = SettingsStore(defaults: d).settings.profiles[0].id
        XCTAssertEqual(first, second,
                       "the store must persist the migrated schema immediately")
    }

    func testProfileAccessorEditsTheFirstProfile() {
        let store = SettingsStore(defaults: freshDefaults())
        store.profile.ssid = "Edited"
        XCTAssertEqual(store.settings.profiles[0].ssid, "Edited")
    }
}
