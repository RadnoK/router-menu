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

    func testHeaderPrefersTheCustomName() {
        var p = ModemProfile.makeDefault(provider: .asus)
        p.name = "Router domowy"
        XCTAssertEqual(PopoverView.headerText(for: p), "Router domowy")
    }

    func testHeaderFallsBackToBrandAndIdentifier() {
        var p = ModemProfile.makeDefault(provider: .asus)
        p.name = ""
        XCTAssertEqual(PopoverView.headerText(for: p), "Asus · 192.168.50.1")
    }

    // MARK: Pane visibility

    private func stats(_ mutate: (inout StatVisibility) -> Void = { _ in }) -> StatVisibility {
        var s = StatVisibility()
        mutate(&s)
        return s
    }

    func testStatusPaneFollowsBasicAndUptime() {
        XCTAssertTrue(PopoverView.showsStatusPane(stats: stats()))
        XCTAssertTrue(PopoverView.showsStatusPane(stats: stats { $0.basic = false }))
        XCTAssertFalse(PopoverView.showsStatusPane(stats: stats {
            $0.basic = false; $0.uptime = false
        }))
    }

    func testSignalPaneNeedsARadioDevice() {
        XCTAssertTrue(PopoverView.showsSignalPane(stats: stats(), hasRadio: true,
                                                  hasChartData: true))
        // An Asus router has no radio to grade — never a signal pane.
        XCTAssertFalse(PopoverView.showsSignalPane(stats: stats(), hasRadio: false,
                                                   hasChartData: true))
        // Rows off, chart on but no data yet → nothing to show.
        XCTAssertFalse(PopoverView.showsSignalPane(stats: stats { $0.radio = false },
                                                   hasRadio: true, hasChartData: false))
        // Rows off, chart on with data → the chart alone earns the pane.
        XCTAssertTrue(PopoverView.showsSignalPane(stats: stats { $0.radio = false },
                                                  hasRadio: true, hasChartData: true))
    }

    func testTransferPaneFollowsRowsAndChart() {
        XCTAssertTrue(PopoverView.showsTransferPane(stats: stats(), hasChartData: false))
        let rowsOff = stats { $0.transfer = false; $0.session = false }
        XCTAssertFalse(PopoverView.showsTransferPane(stats: rowsOff, hasChartData: false))
        XCTAssertTrue(PopoverView.showsTransferPane(stats: rowsOff, hasChartData: true))
        let allOff = stats { $0.transfer = false; $0.session = false; $0.transferChart = false }
        XCTAssertFalse(PopoverView.showsTransferPane(stats: allOff, hasChartData: true))
    }

    func testBatteryPaneNeedsCapabilityToggleAndData() {
        XCTAssertTrue(PopoverView.showsBatteryPane(stats: stats(), hasBattery: true,
                                                   hasChartData: true))
        XCTAssertFalse(PopoverView.showsBatteryPane(stats: stats(), hasBattery: false,
                                                    hasChartData: true))
        XCTAssertFalse(PopoverView.showsBatteryPane(stats: stats { $0.batteryChart = false },
                                                    hasBattery: true, hasChartData: true))
        XCTAssertFalse(PopoverView.showsBatteryPane(stats: stats(), hasBattery: true,
                                                    hasChartData: false))
    }
}
