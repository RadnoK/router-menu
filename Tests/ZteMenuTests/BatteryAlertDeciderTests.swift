import XCTest
@testable import ZteMenu

/// The notifier's whole value is *not* firing: the refresh loop feeds it the
/// same battery reading every 60 s, so anything that alerts on "is below X"
/// rather than "crossed X" would spam the user. These pin the crossing and
/// re-arm rules across a threshold list the user edits freely.
final class BatteryAlertDeciderTests: XCTestCase {
    private func settings(_ thresholds: [BatteryThreshold],
                          fullEnabled: Bool = false) -> BatteryNotificationSettings {
        var s = BatteryNotificationSettings()
        for existing in s.thresholds { s.removeThreshold(id: existing.id) }
        for t in thresholds {
            s.addThreshold(percent: t.percent, isUrgent: t.isUrgent)
            if !t.isEnabled {
                let added = s.thresholds.first { $0.percent == t.percent }!
                s.updateThreshold(id: added.id, isEnabled: false)
            }
        }
        s.fullEnabled = fullEnabled
        return s
    }

    /// The defaults: 20% normal, 10% urgent.
    private let defaults = BatteryNotificationSettings()

    private func decide(_ d: inout BatteryAlertDecider,
                        _ percent: Int,
                        charging: Bool = false,
                        settings s: BatteryNotificationSettings? = nil) -> BatteryAlert? {
        d.decide(percent: percent, isCharging: charging, settings: s ?? defaults)
    }

    func testFirstReadingOnlyEstablishesBaseline() {
        var d = BatteryAlertDecider()
        // Launching with an already-flat battery must not greet the user with
        // an alert — there was no crossing, we just started watching.
        XCTAssertNil(decide(&d, 5))
    }

    func testCrossingAThresholdFiresOnce() {
        var d = BatteryAlertDecider()
        _ = decide(&d, 30)
        XCTAssertEqual(decide(&d, 19), .threshold(percent: 19, isUrgent: false))
        XCTAssertNil(decide(&d, 18), "still below the same threshold — no repeat")
        XCTAssertNil(decide(&d, 17))
    }

    func testEachThresholdFiresOnItsOwnCrossing() {
        var d = BatteryAlertDecider()
        _ = decide(&d, 30)
        XCTAssertEqual(decide(&d, 15), .threshold(percent: 15, isUrgent: false))
        XCTAssertEqual(decide(&d, 9), .threshold(percent: 9, isUrgent: true))
        XCTAssertNil(decide(&d, 8))
    }

    func testDropPastSeveralThresholdsReportsTheLowestOne() {
        var d = BatteryAlertDecider()
        _ = decide(&d, 50)
        // One alert per reading, and the most urgent news wins — the 10%
        // threshold, not the 20% one it also passed.
        XCTAssertEqual(decide(&d, 4), .threshold(percent: 4, isUrgent: true))
        XCTAssertNil(decide(&d, 3), "both thresholds are spent, not just the reported one")
    }

    func testRecoveringAboveHysteresisRearms() {
        var d = BatteryAlertDecider()
        _ = decide(&d, 30)
        XCTAssertEqual(decide(&d, 19), .threshold(percent: 19, isUrgent: false))
        XCTAssertNil(decide(&d, 22), "inside the hysteresis band — still armed-off")
        XCTAssertNil(decide(&d, 19), "so no second alert either")
        _ = decide(&d, 26)  // clears 20 + 5
        XCTAssertEqual(decide(&d, 19), .threshold(percent: 19, isUrgent: false),
                       "re-armed after a real recovery")
    }

    func testChargingSuppressesThresholdAlerts() {
        var d = BatteryAlertDecider()
        _ = decide(&d, 30, charging: true)
        XCTAssertNil(decide(&d, 9, charging: true))
        // And unplugging while still low must not retro-fire: the crossing
        // happened while charging, which is not something to warn about.
        XCTAssertNil(decide(&d, 9))
    }

    func testDisabledThresholdIsSkippedButStillConsumed() {
        let s = settings([BatteryThreshold(percent: 20, isEnabled: false),
                          BatteryThreshold(percent: 10, isUrgent: true)])
        var d = BatteryAlertDecider()
        _ = decide(&d, 30, settings: s)
        XCTAssertNil(decide(&d, 15, settings: s), "the 20% row is off")
        XCTAssertEqual(decide(&d, 5, settings: s), .threshold(percent: 5, isUrgent: true))
    }

    func testAnEmptyListNeverFires() {
        let s = settings([])
        var d = BatteryAlertDecider()
        _ = decide(&d, 80, settings: s)
        XCTAssertNil(decide(&d, 1, settings: s))
    }

    func testAThresholdAddedAfterTheDropFiresOnTheNextReading() {
        var s = settings([BatteryThreshold(percent: 10)])
        var d = BatteryAlertDecider()
        _ = decide(&d, 30, settings: s)
        XCTAssertNil(decide(&d, 15, settings: s))
        // The user adds a 20% threshold while the battery already sits at 15%.
        // It has never fired, so the next reading is its crossing.
        s.addThreshold(percent: 20)
        XCTAssertEqual(decide(&d, 15, settings: s), .threshold(percent: 15, isUrgent: false))
    }

    func testRemovingAThresholdDoesNotRearmTheOthers() {
        var s = settings([BatteryThreshold(percent: 30), BatteryThreshold(percent: 10)])
        var d = BatteryAlertDecider()
        _ = decide(&d, 50, settings: s)
        XCTAssertEqual(decide(&d, 25, settings: s), .threshold(percent: 25, isUrgent: false))

        let removed = s.thresholds.first { $0.percent == 30 }!
        s.removeThreshold(id: removed.id)
        XCTAssertNil(decide(&d, 24, settings: s))
        XCTAssertEqual(decide(&d, 9, settings: s), .threshold(percent: 9, isUrgent: false),
                       "the surviving threshold still fires on its own crossing")
    }

    func testUrgencyComesFromTheThresholdThatFired() {
        let s = settings([BatteryThreshold(percent: 40, isUrgent: true)])
        var d = BatteryAlertDecider()
        _ = decide(&d, 60, settings: s)
        XCTAssertEqual(decide(&d, 35, settings: s), .threshold(percent: 35, isUrgent: true))
    }

    func testFullFiresOnceWhileCharging() {
        let s = settings(BatteryNotificationSettings.defaultThresholds, fullEnabled: true)
        var d = BatteryAlertDecider()
        _ = decide(&d, 90, charging: true, settings: s)
        XCTAssertEqual(decide(&d, 100, charging: true, settings: s), .full)
        XCTAssertNil(decide(&d, 100, charging: true, settings: s))
    }

    func testFullRearmsAfterUnplug() {
        let s = settings(BatteryNotificationSettings.defaultThresholds, fullEnabled: true)
        var d = BatteryAlertDecider()
        _ = decide(&d, 90, charging: true, settings: s)
        XCTAssertEqual(decide(&d, 100, charging: true, settings: s), .full)
        _ = decide(&d, 100, charging: false, settings: s)
        XCTAssertEqual(decide(&d, 100, charging: true, settings: s), .full)
    }

    func testFullNeedsCharging() {
        let s = settings(BatteryNotificationSettings.defaultThresholds, fullEnabled: true)
        var d = BatteryAlertDecider()
        _ = decide(&d, 90, settings: s)
        XCTAssertNil(decide(&d, 100, settings: s), "a full battery on its own is not news")
    }
}
