import XCTest
@testable import ZteMenu

final class ConfigTests: XCTestCase {
    func testRefreshInterval() {
        XCTAssertEqual(Config.refreshInterval, 60)
    }
}
