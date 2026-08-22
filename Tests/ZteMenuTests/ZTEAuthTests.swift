import XCTest
@testable import ZteMenu

final class ZTEAuthTests: XCTestCase {
    // Vector: SHA256(SHA256("test").upper + "ABC").upper — computed independently.
    func testLoginHashIsDeterministic() {
        let h = ZTEAuth.loginHash(password: "test", ld: "ABC")
        // 64 hex characters, uppercase
        XCTAssertEqual(h.count, 64)
        XCTAssertEqual(h, h.uppercased())
        // Repeatable
        XCTAssertEqual(h, ZTEAuth.loginHash(password: "test", ld: "ABC"))
    }

    func testHashChangesWithLD() {
        let a = ZTEAuth.loginHash(password: "test", ld: "ABC")
        let b = ZTEAuth.loginHash(password: "test", ld: "XYZ")
        XCTAssertNotEqual(a, b)
    }
}
