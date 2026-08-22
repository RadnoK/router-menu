import XCTest
@testable import ZteMenu

@MainActor
final class SettingsLanguageTests: XCTestCase {
    private func makeStore() -> SettingsStore {
        let suite = UserDefaults(suiteName: "test-\(UUID().uuidString)")!
        return SettingsStore(defaults: suite)
    }

    func testLanguageDefaultsToSystem() {
        XCTAssertEqual(makeStore().settings.language, .system)
    }

    func testLanguagePersistsAcrossStoreInstances() {
        let suite = UserDefaults(suiteName: "test-\(UUID().uuidString)")!
        let store = SettingsStore(defaults: suite)
        store.settings.language = .en
        let reloaded = SettingsStore(defaults: suite)
        XCTAssertEqual(reloaded.settings.language, .en)
    }

    func testDecodingSettingsWithoutLanguageFieldDefaultsToSystem() throws {
        // Users upgrading from 0.2.1 have stored settings with no language key.
        // Decoding must not throw and must land on .system.
        let legacy = #"{"networkMode":"bySSID","ssid":"ZTE","modemIP":"192.168.0.1","refreshInterval":60,"stats":{"basic":true,"radio":true,"transfer":true,"uptime":true}}"#
        let decoded = try JSONDecoder().decode(AppSettings.self, from: Data(legacy.utf8))
        XCTAssertEqual(decoded.language, .system)
    }

    func testLastCheckLabelUsesNeverCheckedKeyWhenNil() {
        let l10n = L10n(language: .en)
        XCTAssertEqual(SettingsView.lastCheckLabel(nil, l10n: l10n), l10n(.settingsNeverChecked))
    }

    func testLastCheckLabelIncludesRelativeDate() {
        let l10n = L10n(language: .en)
        let label = SettingsView.lastCheckLabel(Date(timeIntervalSinceNow: -3600), l10n: l10n)
        XCTAssertNotEqual(label, l10n(.settingsNeverChecked))
        XCTAssertFalse(label.isEmpty)
    }
}
