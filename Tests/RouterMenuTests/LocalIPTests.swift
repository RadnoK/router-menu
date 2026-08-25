import XCTest
@testable import RouterMenu

final class LocalIPTests: XCTestCase {
    func testRouteTowardsLoopbackIsLoopback() {
        // The one deterministic route on every machine.
        XCTAssertEqual(LocalIP.address(towards: "127.0.0.1"), "127.0.0.1")
    }

    func testGarbageHostResolvesToNil() {
        XCTAssertNil(LocalIP.address(towards: "not an ip"))
        XCTAssertNil(LocalIP.address(towards: ""))
    }
}
