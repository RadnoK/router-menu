import XCTest
@testable import ZteMenu

final class KeychainTests: XCTestCase {
    override func tearDown() {
        Keychain.deletePassword()
        super.tearDown()
    }

    func testSetGetDelete() {
        Keychain.deletePassword()
        XCTAssertNil(Keychain.password())

        Keychain.setPassword("tajne")
        XCTAssertEqual(Keychain.password(), "tajne")

        Keychain.setPassword("nowe")
        XCTAssertEqual(Keychain.password(), "nowe")

        Keychain.deletePassword()
        XCTAssertNil(Keychain.password())
    }
}
