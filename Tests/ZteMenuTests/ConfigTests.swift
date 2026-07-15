import XCTest
@testable import ZteMenu

final class ConfigTests: XCTestCase {
    func testDefaults() {
        XCTAssertEqual(Config.modemBaseURL.absoluteString, "http://192.168.0.1")
        XCTAssertEqual(Config.targetSSID, "ZTE_B4B622")
        XCTAssertEqual(Config.refreshInterval, 60)
    }
}
