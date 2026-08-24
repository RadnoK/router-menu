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
        XCTAssertEqual(store.profile.ssid, "ZTE_B4B622")
        XCTAssertEqual(store.profile.modemIP, "192.168.0.1")
        XCTAssertEqual(store.profile.matchMode, .ssid)
        XCTAssertEqual(store.settings.refreshInterval, 60)
        XCTAssertTrue(store.profile.stats.basic)
        XCTAssertTrue(store.profile.stats.transfer)
        XCTAssertFalse(store.settings.showWhenDisconnected, "the icon hides by default")
    }

    func testPersistsAcrossInstances() {
        let d = freshDefaults()
        let a = SettingsStore(defaults: d)
        a.profile.ssid = "MyZTE"
        a.profile.matchMode = .ipProbe
        a.save()

        let b = SettingsStore(defaults: d)
        XCTAssertEqual(b.profile.ssid, "MyZTE")
        XCTAssertEqual(b.profile.matchMode, .ipProbe)
    }

    func testBatteryDefaults() {
        let store = SettingsStore(defaults: freshDefaults())
        XCTAssertFalse(store.profile.showBatteryPercent, "the percentage is opt-in")
        let alerts = store.profile.batteryNotifications
        XCTAssertEqual(alerts.thresholds.map(\.percent), [20, 10])
        XCTAssertTrue(alerts.thresholds.allSatisfy(\.isEnabled))
        XCTAssertFalse(alerts.fullEnabled)
    }

    func testPayloadWithoutBatteryKeysStillLoads() throws {
        let d = freshDefaults()
        let legacy = Data(#"{"networkMode":"byIPReachable","ssid":"MyZTE","modemIP":"10.0.0.1","refreshInterval":30,"stats":{"basic":false,"radio":true,"transfer":true,"uptime":true},"language":"pl"}"#.utf8)
        d.set(legacy, forKey: "zte.settings")

        let store = SettingsStore(defaults: d)
        XCTAssertEqual(store.profile.ssid, "MyZTE")
        XCTAssertEqual(store.settings.language, .pl)
        XCTAssertFalse(store.profile.stats.basic)
        XCTAssertFalse(store.profile.showBatteryPercent)
        XCTAssertFalse(store.settings.showWhenDisconnected)
        XCTAssertEqual(store.profile.batteryNotifications, BatteryNotificationSettings())
    }

    func testBatterySettingsPersist() {
        let d = freshDefaults()
        let a = SettingsStore(defaults: d)
        a.profile.showBatteryPercent = true
        a.profile.batteryNotifications.addThreshold(percent: 35, isUrgent: true)
        a.profile.batteryNotifications.fullEnabled = true
        a.save()

        let b = SettingsStore(defaults: d)
        XCTAssertTrue(b.profile.showBatteryPercent)
        XCTAssertEqual(b.profile.batteryNotifications.thresholds.map(\.percent), [35, 20, 10])
        XCTAssertTrue(b.profile.batteryNotifications.fullEnabled)
    }

    func testProfileBaseURL() {
        let store = SettingsStore(defaults: freshDefaults())
        store.profile.modemIP = "192.168.1.1"
        XCTAssertEqual(store.profile.baseURL.absoluteString, "http://192.168.1.1")
    }

    func testProfileAccessorFollowsTheSelection() {
        let store = SettingsStore(defaults: freshDefaults())
        let secondID = store.settings.addProfile(provider: .asus)
        XCTAssertEqual(store.profile.provider, .zte, "nil selection falls back to the first profile")

        store.editedProfileID = secondID
        XCTAssertEqual(store.profile.provider, .asus)

        store.profile.name = "Router"
        XCTAssertEqual(store.settings.profiles[1].name, "Router",
                       "the setter writes back to the SELECTED profile by id")
        XCTAssertEqual(store.settings.profiles[0].name, "")
    }

    func testStaleSelectionFallsBackToTheFirstProfile() {
        let store = SettingsStore(defaults: freshDefaults())
        store.editedProfileID = UUID()
        XCTAssertEqual(store.profile.id, store.settings.profiles[0].id)
    }
}
