import XCTest
@testable import ZteMenu

final class DeviceDetailTabTests: XCTestCase {
    func testBatteryTabOnlyForBatteryCapableProviders() {
        XCTAssertEqual(DeviceDetailTab.available(for: .zte),
                       [.info, .signIn, .stats, .battery])
        XCTAssertEqual(DeviceDetailTab.available(for: .asus),
                       [.info, .signIn, .stats],
                       "a mains-powered router has no battery segment")
    }

    func testEveryTabHasADistinctTitleKey() {
        let keys = DeviceDetailTab.allCases.map(\.titleKey)
        XCTAssertEqual(Set(keys).count, keys.count, "segments must not share a title")
    }

    func testConnectionFailureMapsToTheRightMessage() {
        XCTAssertEqual(DeviceSignInSection.failureKey(for: ModemError.loginFailed),
                       .errorLoginFailed)
        struct Boom: Error {}
        XCTAssertEqual(DeviceSignInSection.failureKey(for: Boom()), .errorUnreachable)
    }
}
