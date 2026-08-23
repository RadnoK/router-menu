import XCTest
@testable import ZteMenu

@MainActor
final class SettingsStoreTests: XCTestCase {
    private func freshDefaults() -> UserDefaults {
        let d = UserDefaults(suiteName: "test-\(UUID().uuidString)")!
        return d
    }

    func testDefaults() {
        let store = SettingsStore(defaults: freshDefaults())
        XCTAssertEqual(store.settings.ssid, "ZTE_B4B622")
        XCTAssertEqual(store.settings.modemIP, "192.168.0.1")
        XCTAssertEqual(store.settings.networkMode, .bySSID)
        XCTAssertEqual(store.settings.refreshInterval, 60)
        XCTAssertTrue(store.settings.stats.basic)
        XCTAssertTrue(store.settings.stats.transfer)
        XCTAssertFalse(store.settings.showWhenDisconnected, "the icon hides by default")
    }

    func testPersistsAcrossInstances() {
        let d = freshDefaults()
        let a = SettingsStore(defaults: d)
        a.settings.ssid = "MyZTE"
        a.settings.networkMode = .byIPReachable
        a.save()

        let b = SettingsStore(defaults: d)
        XCTAssertEqual(b.settings.ssid, "MyZTE")
        XCTAssertEqual(b.settings.networkMode, .byIPReachable)
    }

    func testBatteryDefaults() {
        let store = SettingsStore(defaults: freshDefaults())
        XCTAssertFalse(store.settings.showBatteryPercent, "the percentage is opt-in")
        let alerts = store.settings.batteryNotifications
        XCTAssertEqual(alerts.thresholds.map(\.percent), [20, 10])
        XCTAssertTrue(alerts.thresholds.allSatisfy(\.isEnabled))
        XCTAssertFalse(alerts.fullEnabled)
    }

    func testPayloadWithoutBatteryKeysStillLoads() throws {
        // What a 0.4.x install has on disk. Every other preference must survive
        // the upgrade rather than silently reset to defaults.
        let d = freshDefaults()
        let legacy = Data(#"{"networkMode":"byIPReachable","ssid":"MyZTE","modemIP":"10.0.0.1","refreshInterval":30,"stats":{"basic":false,"radio":true,"transfer":true,"uptime":true},"language":"pl"}"#.utf8)
        d.set(legacy, forKey: "zte.settings")

        let store = SettingsStore(defaults: d)
        XCTAssertEqual(store.settings.ssid, "MyZTE")
        XCTAssertEqual(store.settings.language, .pl)
        XCTAssertFalse(store.settings.stats.basic)
        XCTAssertFalse(store.settings.showBatteryPercent)
        XCTAssertFalse(store.settings.showWhenDisconnected)
        XCTAssertEqual(store.settings.batteryNotifications, BatteryNotificationSettings())
    }

    func testBatterySettingsPersist() {
        let d = freshDefaults()
        let a = SettingsStore(defaults: d)
        a.settings.showBatteryPercent = true
        a.settings.batteryNotifications.addThreshold(percent: 35, isUrgent: true)
        a.settings.batteryNotifications.fullEnabled = true
        a.save()

        let b = SettingsStore(defaults: d)
        XCTAssertTrue(b.settings.showBatteryPercent)
        XCTAssertEqual(b.settings.batteryNotifications.thresholds.map(\.percent), [35, 20, 10])
        XCTAssertTrue(b.settings.batteryNotifications.fullEnabled)
    }

    func testModemBaseURL() {
        let store = SettingsStore(defaults: freshDefaults())
        store.settings.modemIP = "192.168.1.1"
        XCTAssertEqual(store.modemBaseURL.absoluteString, "http://192.168.1.1")
    }
}
