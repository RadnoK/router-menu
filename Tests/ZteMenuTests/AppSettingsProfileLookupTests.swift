import XCTest
@testable import ZteMenu

final class AppSettingsProfileLookupTests: XCTestCase {
    func testFindsTheStoredProfileById() {
        var s = AppSettings()
        s.profiles[0].showBatteryPercent = true
        XCTAssertEqual(s.profile(with: s.profiles[0].id)?.showBatteryPercent, true)
    }

    func testUnknownOrNilIdReturnsNil() {
        let s = AppSettings()
        XCTAssertNil(s.profile(with: UUID()))
        XCTAssertNil(s.profile(with: nil))
    }
}
