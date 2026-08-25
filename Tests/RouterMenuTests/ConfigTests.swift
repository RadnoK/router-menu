import XCTest
@testable import RouterMenu

final class ConfigTests: XCTestCase {
    func testRefreshInterval() {
        XCTAssertEqual(Config.refreshInterval, 60)
    }
}
