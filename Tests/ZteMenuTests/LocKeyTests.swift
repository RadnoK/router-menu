import XCTest
@testable import ZteMenu

final class LocKeyTests: XCTestCase {
    func testRawValuesAreUnique() {
        let raw = LocKey.allCases.map(\.rawValue)
        XCTAssertEqual(Set(raw).count, raw.count, "duplicate LocKey raw values")
    }

    func testRawValuesUseDottedNamespaces() {
        for key in LocKey.allCases {
            XCTAssertTrue(key.rawValue.contains("."),
                          "\(key.rawValue) should be namespaced, e.g. popover.refresh")
            XCTAssertFalse(key.rawValue.hasSuffix("."), "\(key.rawValue) has a trailing dot")
        }
    }

    func testCatalogueIsNotEmpty() {
        XCTAssertGreaterThan(LocKey.allCases.count, 30)
    }
}
