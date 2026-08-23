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

    func testHeaderShowsBrandAndSSIDWhenMatchedBySSID() {
        var p = ModemProfile.makeDefault(provider: .zte)
        p.matchMode = .ssid
        p.ssid = "ZTE_B4B622"
        XCTAssertEqual(PopoverView.headerText(for: p), "ZTE · ZTE_B4B622")
    }

    func testHeaderShowsBrandAndIPWhenMatchedByProbe() {
        var p = ModemProfile.makeDefault(provider: .zte)
        p.matchMode = .ipProbe
        p.modemIP = "10.0.0.1"
        XCTAssertEqual(PopoverView.headerText(for: p), "ZTE · 10.0.0.1")
    }
}
