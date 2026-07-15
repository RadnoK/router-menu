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

    func testModemBaseURL() {
        let store = SettingsStore(defaults: freshDefaults())
        store.settings.modemIP = "192.168.1.1"
        XCTAssertEqual(store.modemBaseURL.absoluteString, "http://192.168.1.1")
    }
}
