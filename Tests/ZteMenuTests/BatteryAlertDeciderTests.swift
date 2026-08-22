import XCTest
@testable import ZteMenu

/// The notifier's whole value is *not* firing: the refresh loop feeds it the
/// same battery reading every 60 s, so anything that alerts on "is below X"
/// rather than "crossed X" would spam the user. These pin the crossing and
/// re-arm rules.
final class BatteryAlertDeciderTests: XCTestCase {
    private let config = BatteryNotificationSettings()  // low 20, critical 10, full off

    private func decide(_ decider: inout BatteryAlertDecider,
                        _ percent: Int,
                        charging: Bool = false,
                        settings: BatteryNotificationSettings? = nil) -> BatteryAlert? {
        decider.decide(percent: percent, isCharging: charging, settings: settings ?? config)
    }

    func testFirstReadingOnlyEstablishesBaseline() {
        var d = BatteryAlertDecider()
        // Launching with an already-flat battery must not greet the user with
        // "critical" — there was no crossing, we just started watching.
        XCTAssertNil(decide(&d, 5))
    }

    func testCrossingLowThresholdFiresOnce() {
        var d = BatteryAlertDecider()
        _ = decide(&d, 30)
        XCTAssertEqual(decide(&d, 19), .low(19))
        XCTAssertNil(decide(&d, 18), "still below the same threshold — no repeat")
        XCTAssertNil(decide(&d, 17))
    }

    func testCrossingCriticalFiresEvenAfterLow() {
        var d = BatteryAlertDecider()
        _ = decide(&d, 30)
        XCTAssertEqual(decide(&d, 15), .low(15))
        XCTAssertEqual(decide(&d, 9), .critical(9))
        XCTAssertNil(decide(&d, 8))
    }

    func testDropStraightPastBothReportsCriticalOnly() {
        var d = BatteryAlertDecider()
        _ = decide(&d, 50)
        // One alert per reading, and the more urgent one wins.
        XCTAssertEqual(decide(&d, 4), .critical(4))
        XCTAssertNil(decide(&d, 3))
    }

    func testRecoveringAboveHysteresisRearms() {
        var d = BatteryAlertDecider()
        _ = decide(&d, 30)
        XCTAssertEqual(decide(&d, 19), .low(19))
        XCTAssertNil(decide(&d, 22), "inside the hysteresis band — still armed-off")
        XCTAssertNil(decide(&d, 19), "so no second alert either")
        _ = decide(&d, 26)  // clears 20 + 5
        XCTAssertEqual(decide(&d, 19), .low(19), "re-armed after a real recovery")
    }

    func testChargingSuppressesLowAndCritical() {
        var d = BatteryAlertDecider()
        _ = decide(&d, 30, charging: true)
        XCTAssertNil(decide(&d, 9, charging: true))
        // And unplugging while still low must not retro-fire: the crossing
        // happened while charging, which is not something to warn about.
        XCTAssertNil(decide(&d, 9))
    }

    func testDisabledThresholdNeverFires() {
        var s = config
        s.lowEnabled = false
        var d = BatteryAlertDecider()
        _ = decide(&d, 30, settings: s)
        XCTAssertNil(decide(&d, 15, settings: s))
        XCTAssertEqual(decide(&d, 5, settings: s), .critical(5), "critical is independent")
    }

    func testFullFiresOnceWhileCharging() {
        var s = config
        s.fullEnabled = true
        var d = BatteryAlertDecider()
        _ = decide(&d, 90, charging: true, settings: s)
        XCTAssertEqual(decide(&d, 100, charging: true, settings: s), .full)
        XCTAssertNil(decide(&d, 100, charging: true, settings: s))
    }

    func testFullRearmsAfterUnplug() {
        var s = config
        s.fullEnabled = true
        var d = BatteryAlertDecider()
        _ = decide(&d, 90, charging: true, settings: s)
        XCTAssertEqual(decide(&d, 100, charging: true, settings: s), .full)
        _ = decide(&d, 100, charging: false, settings: s)
        XCTAssertEqual(decide(&d, 100, charging: true, settings: s), .full)
    }

    func testFullNeedsCharging() {
        var s = config
        s.fullEnabled = true
        var d = BatteryAlertDecider()
        _ = decide(&d, 90, settings: s)
        XCTAssertNil(decide(&d, 100, settings: s), "a full battery on its own is not news")
    }

    func testCustomThresholdsAreRespected() {
        var s = BatteryNotificationSettings(lowEnabled: true, lowThreshold: 50,
                                            criticalEnabled: true, criticalThreshold: 40,
                                            fullEnabled: false)
        var d = BatteryAlertDecider()
        _ = decide(&d, 60, settings: s)
        XCTAssertEqual(decide(&d, 45, settings: s), .low(45))
        XCTAssertEqual(decide(&d, 39, settings: s), .critical(39))
        s.lowThreshold = 80
        // Lowering the battery further under a raised threshold: already fired
        // for `low`, and re-arming is driven by recovery, not by config edits.
        XCTAssertNil(decide(&d, 38, settings: s))
    }
}
