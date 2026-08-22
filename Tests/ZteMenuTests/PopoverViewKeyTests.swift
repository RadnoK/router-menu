import XCTest
@testable import ZteMenu

@MainActor
final class PopoverViewKeyTests: XCTestCase {
    func testSignalQualityMapsToExpectedKeys() {
        XCTAssertEqual(PopoverView.key(for: .noSignal), .signalNone)
        XCTAssertEqual(PopoverView.key(for: .veryWeak), .signalVeryWeak)
        XCTAssertEqual(PopoverView.key(for: .weak), .signalWeak)
        XCTAssertEqual(PopoverView.key(for: .medium), .signalMedium)
        XCTAssertEqual(PopoverView.key(for: .good), .signalGood)
        XCTAssertEqual(PopoverView.key(for: .veryGood), .signalVeryGood)
    }

    func testErrorKindMapsToExpectedKeys() {
        XCTAssertEqual(PopoverView.key(for: .loginFailed), .errorLoginFailed)
        XCTAssertEqual(PopoverView.key(for: .unreachable), .errorUnreachable)
    }
}
