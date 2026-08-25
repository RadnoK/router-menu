import XCTest
@testable import RouterMenu

final class MenuBarPresentationTests: XCTestCase {
    private func data(bars: Int, battery: Int? = nil) -> ModemData {
        var raw = ["signalbar": "\(bars)", "network_type": "ENDC", "ppp_status": "ppp_connected"]
        if let battery { raw["battery_value"] = "\(battery)" }
        return ZTEClient.parse(raw)
    }

    func testHiddenIsInvisible() {
        XCTAssertFalse(MenuBarPresentation.make(for: .hidden).isVisible)
    }

    func testHiddenStaysVisibleWhenTheUserAsksForIt() {
        let p = MenuBarPresentation.make(for: .hidden, showWhenDisconnected: true)
        XCTAssertTrue(p.isVisible)
        XCTAssertEqual(p.symbolName, "antenna.radiowaves.left.and.right.slash")
        XCTAssertEqual(p.variableValue, 0)
    }

    func testHiddenCarriesNoBatteryTextEvenWhenBothOptionsAreOn() {
        // Nothing was read from the modem, so there is no level to show.
        let p = MenuBarPresentation.make(for: .hidden,
                                         showBatteryPercent: true,
                                         showWhenDisconnected: true)
        XCTAssertNil(p.batteryText)
    }

    func testShowWhenDisconnectedLeavesConnectedUntouched() {
        let p = MenuBarPresentation.make(for: .connected(data(bars: 4)), showWhenDisconnected: true)
        XCTAssertEqual(p.symbolName, "cellularbars")
        XCTAssertEqual(p.variableValue, 0.8, accuracy: 0.001)
    }

    func testConnectedUsesCellularbars() {
        let p = MenuBarPresentation.make(for: .connected(data(bars: 4)))
        XCTAssertTrue(p.isVisible)
        XCTAssertEqual(p.symbolName, "cellularbars")
        XCTAssertEqual(p.variableValue, 0.8, accuracy: 0.001) // 4/5
    }

    func testNoSignalUsesSlashSymbol() {
        let p = MenuBarPresentation.make(for: .connected(data(bars: 0)))
        XCTAssertEqual(p.symbolName, "antenna.radiowaves.left.and.right.slash")
    }

    func testErrorIsVisibleWithSlash() {
        let p = MenuBarPresentation.make(for: .error(.unreachable))
        XCTAssertTrue(p.isVisible)
        XCTAssertEqual(p.symbolName, "antenna.radiowaves.left.and.right.slash")
    }

    func testLocationDeniedIsVisible() {
        XCTAssertTrue(MenuBarPresentation.make(for: .locationDenied).isVisible)
    }

    func testBatteryTextIsAbsentByDefault() {
        let p = MenuBarPresentation.make(for: .connected(data(bars: 4, battery: 72)))
        XCTAssertNil(p.batteryText, "the percentage is opt-in")
    }

    func testBatteryTextWhenEnabled() {
        let p = MenuBarPresentation.make(for: .connected(data(bars: 4, battery: 72)),
                                         showBatteryPercent: true)
        XCTAssertEqual(p.batteryText, "72%")
    }

    func testBatteryTextOmittedWhenModemReportsNoLevel() {
        let p = MenuBarPresentation.make(for: .connected(data(bars: 4)), showBatteryPercent: true)
        XCTAssertNil(p.batteryText)
    }

    func testBatteryTextOmittedWhenDisconnected() {
        for state in [AppState.error(.unreachable), .locationDenied] {
            XCTAssertNil(MenuBarPresentation.make(for: state, showBatteryPercent: true).batteryText)
        }
    }

    func testConnectedRadiolessDeviceShowsTheRouterSymbol() {
        let d = ZTEClient.parse(["signalbar": "0", "network_type": "DHCP",
                                 "battery_value": ""])
        let p = MenuBarPresentation.make(for: .connected(d),
                                         showBatteryPercent: true,
                                         showWhenDisconnected: false,
                                         showsRadioSignal: false)
        XCTAssertTrue(p.isVisible)
        XCTAssertEqual(p.symbolName, "wifi.router")
        XCTAssertNil(p.batteryText, "a battery-less reading shows no percentage")
    }

    func testConnectedRadioDeviceKeepsTheExistingSymbols() {
        let d = ZTEClient.parse(["signalbar": "4", "network_type": "ENDC",
                                 "battery_value": "80"])
        let p = MenuBarPresentation.make(for: .connected(d),
                                         showBatteryPercent: true,
                                         showWhenDisconnected: false,
                                         showsRadioSignal: true)
        XCTAssertEqual(p.symbolName, "cellularbars")
        XCTAssertEqual(p.batteryText, "80%")
    }
}
