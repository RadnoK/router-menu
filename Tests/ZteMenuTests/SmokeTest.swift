import XCTest
@testable import ZteMenu

final class SmokeTest: XCTestCase {
    func testBuildMarker() {
        XCTAssertTrue(ZteMenuBuildMarker.ok)
    }
}
