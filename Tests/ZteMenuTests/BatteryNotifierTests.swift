import XCTest
@testable import ZteMenu

@MainActor
private final class SpyPresenter: BatteryAlertPresenting {
    var presented: [BatteryAlert] = []
    var authorizationRequests = 0
    func present(_ alert: BatteryAlert) { presented.append(alert) }
    func requestAuthorization() { authorizationRequests += 1 }
}

@MainActor
final class BatteryNotifierTests: XCTestCase {
    private func makeSettings() -> SettingsStore {
        SettingsStore(defaults: UserDefaults(suiteName: "bn-\(UUID().uuidString)")!)
    }

    private func reading(_ percent: Int) -> ModemData {
        ZTEClient.parse(["battery_value": "\(percent)", "battery_charging": "0",
                         "signalbar": "5", "network_type": "ENDC"])
    }

    func testReadsTheProfilesOwnConfiguration() {
        let settings = makeSettings()
        var profile = ModemProfile.makeDefault(provider: .zte)
        // Only one threshold, at 50 — NOT the defaults (20/10) — so an alert
        // at 45 proves the notifier read the profile, not a global.
        for t in profile.batteryNotifications.thresholds {
            profile.batteryNotifications.removeThreshold(id: t.id)
        }
        profile.batteryNotifications.addThreshold(percent: 50)
        let spy = SpyPresenter()
        let notifier = BatteryNotifier(settings: settings, presenter: spy)

        notifier.handle(reading(60), profile: profile)   // baseline
        notifier.handle(reading(45), profile: profile)   // crossing

        XCTAssertEqual(spy.presented, [.threshold(percent: 45, isUrgent: false)])
    }

    func testSwitchingProfilesResetsTheDecider() {
        // A new device's first reading is a baseline, not a crossing: profile
        // B sitting at 15% must stay quiet even though profile A armed
        // nothing at that level.
        let settings = makeSettings()
        let a = ModemProfile.makeDefault(provider: .zte)
        let b = ModemProfile.makeDefault(provider: .zte)
        let spy = SpyPresenter()
        let notifier = BatteryNotifier(settings: settings, presenter: spy)

        notifier.handle(reading(100), profile: a)  // A's baseline, high
        notifier.handle(reading(15), profile: b)   // B appears already low

        XCTAssertTrue(spy.presented.isEmpty,
                      "a level the new device was already at is not a crossing")
    }

    func testSameProfileKeepsItsDeciderMemory() {
        let settings = makeSettings()
        let profile = ModemProfile.makeDefault(provider: .zte)  // thresholds 20/10
        let spy = SpyPresenter()
        let notifier = BatteryNotifier(settings: settings, presenter: spy)

        notifier.handle(reading(60), profile: profile)
        notifier.handle(reading(15), profile: profile)  // crosses 20 → fires
        notifier.handle(reading(14), profile: profile)  // still below → quiet

        XCTAssertEqual(spy.presented.count, 1)
    }

    func testAuthorizationPromptScansTheProfiles() {
        let settings = makeSettings()  // default ZTE profile, thresholds armed
        let spy = SpyPresenter()
        BatteryNotifier(settings: settings, presenter: spy).requestAuthorizationIfNeeded()
        XCTAssertEqual(spy.authorizationRequests, 1)
    }

    func testNoArmedAlertMeansNoPrompt() {
        let settings = makeSettings()
        for t in settings.profile.batteryNotifications.thresholds {
            settings.profile.batteryNotifications.updateThreshold(id: t.id, isEnabled: false)
        }
        settings.profile.batteryNotifications.fullEnabled = false
        let spy = SpyPresenter()
        BatteryNotifier(settings: settings, presenter: spy).requestAuthorizationIfNeeded()
        XCTAssertEqual(spy.authorizationRequests, 0)
    }
}
