import XCTest
@testable import ZteMenu

/// The two thresholds are edited by independent steppers, so the model is what
/// keeps them from crossing — these pin which value gives way.
final class BatteryNotificationSettingsTests: XCTestCase {
    func testNonOverlappingThresholdsAreLeftAlone() {
        var s = BatteryNotificationSettings()
        s.resolveThresholdOverlap(movedCritical: true)
        XCTAssertEqual(s, BatteryNotificationSettings())
    }

    func testRaisingCriticalPushesLowUp() {
        var s = BatteryNotificationSettings()
        s.criticalThreshold = 20  // equal to low
        s.resolveThresholdOverlap(movedCritical: true)
        XCTAssertEqual(s.criticalThreshold, 20)
        XCTAssertEqual(s.lowThreshold, 25)
    }

    func testLoweringLowPushesCriticalDown() {
        var s = BatteryNotificationSettings()
        s.lowThreshold = 10  // equal to critical
        s.resolveThresholdOverlap(movedCritical: false)
        XCTAssertEqual(s.lowThreshold, 10)
        XCTAssertEqual(s.criticalThreshold, 5)
    }

    func testCriticalGivesWayAtTheTopOfTheRange() {
        var s = BatteryNotificationSettings()
        s.lowThreshold = 95
        s.criticalThreshold = 95
        s.resolveThresholdOverlap(movedCritical: true)
        // `low` cannot go above 95, so the value the user moved is the one
        // clamped instead — both stay inside the range and stay ordered.
        XCTAssertEqual(s.lowThreshold, 95)
        XCTAssertEqual(s.criticalThreshold, 90)
    }

    func testLowGivesWayAtTheBottomOfTheRange() {
        var s = BatteryNotificationSettings()
        s.lowThreshold = 5
        s.criticalThreshold = 5
        s.resolveThresholdOverlap(movedCritical: false)
        XCTAssertEqual(s.criticalThreshold, 5)
        XCTAssertEqual(s.lowThreshold, 10)
    }

    func testIsAnyEnabled() {
        var s = BatteryNotificationSettings(lowEnabled: false, lowThreshold: 20,
                                            criticalEnabled: false, criticalThreshold: 10,
                                            fullEnabled: false)
        XCTAssertFalse(s.isAnyEnabled)
        s.fullEnabled = true
        XCTAssertTrue(s.isAnyEnabled)
    }
}
