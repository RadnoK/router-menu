import XCTest
@testable import RouterMenu

/// The threshold list is edited directly by the user, so the model is what
/// keeps it ordered, unique and inside the range the UI promises.
final class BatteryNotificationSettingsTests: XCTestCase {
    func testDefaultsAreTwentyAndTenUrgent() {
        let s = BatteryNotificationSettings()
        XCTAssertEqual(s.thresholds.map(\.percent), [20, 10])
        XCTAssertEqual(s.thresholds.map(\.isUrgent), [false, true])
        XCTAssertTrue(s.thresholds.allSatisfy(\.isEnabled))
        XCTAssertFalse(s.fullEnabled)
    }

    func testAddingKeepsTheListSortedHighToLow() {
        var s = BatteryNotificationSettings()
        XCTAssertTrue(s.addThreshold(percent: 50))
        XCTAssertTrue(s.addThreshold(percent: 5))
        XCTAssertEqual(s.thresholds.map(\.percent), [50, 20, 10, 5])
    }

    func testDuplicatePercentagesAreRejected() {
        var s = BatteryNotificationSettings()
        XCTAssertFalse(s.addThreshold(percent: 20), "20% already exists")
        XCTAssertEqual(s.thresholds.count, 2)
    }

    func testOutOfRangePercentagesAreRejected() {
        var s = BatteryNotificationSettings()
        XCTAssertFalse(s.addThreshold(percent: 0))
        XCTAssertFalse(s.addThreshold(percent: 100), "a full battery is the separate alert")
        XCTAssertFalse(s.addThreshold(percent: -5))
        XCTAssertEqual(s.thresholds.count, 2)
    }

    func testRemoving() {
        var s = BatteryNotificationSettings()
        let id = s.thresholds[0].id
        s.removeThreshold(id: id)
        XCTAssertEqual(s.thresholds.map(\.percent), [10])
    }

    func testRemovingAnUnknownIDChangesNothing() {
        var s = BatteryNotificationSettings()
        s.removeThreshold(id: UUID())
        XCTAssertEqual(s.thresholds.count, 2)
    }

    func testUpdatingAPercentageResorts() {
        var s = BatteryNotificationSettings()
        let id = s.thresholds.first { $0.percent == 10 }!.id
        XCTAssertTrue(s.updateThreshold(id: id, percent: 60))
        XCTAssertEqual(s.thresholds.map(\.percent), [60, 20])
    }

    func testUpdatingOntoAnotherRowsPercentageIsRejected() {
        var s = BatteryNotificationSettings()
        let id = s.thresholds.first { $0.percent == 10 }!.id
        XCTAssertFalse(s.updateThreshold(id: id, percent: 20))
        XCTAssertEqual(s.thresholds.map(\.percent), [20, 10], "the edit was dropped")
    }

    func testUpdatingToItsOwnPercentageIsAllowed() {
        var s = BatteryNotificationSettings()
        let id = s.thresholds[0].id
        XCTAssertTrue(s.updateThreshold(id: id, percent: 20, isUrgent: true))
        XCTAssertTrue(s.thresholds[0].isUrgent)
    }

    func testUpdatingFlags() {
        var s = BatteryNotificationSettings()
        let id = s.thresholds[0].id
        XCTAssertTrue(s.updateThreshold(id: id, isEnabled: false))
        XCTAssertFalse(s.thresholds[0].isEnabled)
    }

    func testIsAnyEnabled() {
        var s = BatteryNotificationSettings()
        XCTAssertTrue(s.isAnyEnabled)
        for t in s.thresholds { s.updateThreshold(id: t.id, isEnabled: false) }
        XCTAssertFalse(s.isAnyEnabled)
        s.fullEnabled = true
        XCTAssertTrue(s.isAnyEnabled, "the charging alert counts too")
    }

    func testSuggestedThresholdSitsBelowTheLowestRow() {
        var s = BatteryNotificationSettings()
        XCTAssertEqual(s.suggestedNewThreshold, 5)
        s.addThreshold(percent: 5)
        XCTAssertEqual(s.suggestedNewThreshold, 1, "no room for another step of five")
    }

    func testSuggestedThresholdOnAnEmptyList() {
        var s = BatteryNotificationSettings()
        for t in s.thresholds { s.removeThreshold(id: t.id) }
        XCTAssertEqual(s.suggestedNewThreshold, 20)
    }

    func testSuggestedThresholdSkipsTakenSlotsAtTheBottom() {
        var s = BatteryNotificationSettings()
        for t in s.thresholds { s.removeThreshold(id: t.id) }
        for p in 1...4 { s.addThreshold(percent: p) }
        XCTAssertEqual(s.suggestedNewThreshold, 5, "1–4 are taken")
    }

    func testDecodingAPayloadWithoutThresholdsFallsBackToDefaults() throws {
        // What a settings blob written before the list existed looks like: the
        // old fixed low/critical keys, which have no meaning any more.
        let legacy = Data(#"{"lowEnabled":true,"lowThreshold":35,"criticalEnabled":true,"criticalThreshold":15,"fullEnabled":true}"#.utf8)
        let decoded = try JSONDecoder().decode(BatteryNotificationSettings.self, from: legacy)
        XCTAssertEqual(decoded.thresholds.map(\.percent), [20, 10])
        XCTAssertTrue(decoded.fullEnabled, "a key that still means the same thing is kept")
    }

    func testRoundTripsThroughCoding() throws {
        var s = BatteryNotificationSettings()
        s.addThreshold(percent: 45, isUrgent: true)
        s.fullEnabled = true
        let data = try JSONEncoder().encode(s)
        XCTAssertEqual(try JSONDecoder().decode(BatteryNotificationSettings.self, from: data), s)
    }

    func testDecodingSortsAHandEditedPayload() throws {
        let data = Data(#"{"thresholds":[{"id":"00000000-0000-0000-0000-000000000001","percent":5,"isUrgent":false,"isEnabled":true},{"id":"00000000-0000-0000-0000-000000000002","percent":50,"isUrgent":false,"isEnabled":true}],"fullEnabled":false}"#.utf8)
        let decoded = try JSONDecoder().decode(BatteryNotificationSettings.self, from: data)
        XCTAssertEqual(decoded.thresholds.map(\.percent), [50, 5])
    }
}
