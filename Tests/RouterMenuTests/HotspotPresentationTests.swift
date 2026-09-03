import XCTest
@testable import RouterMenu

/// A tethered phone needs its own menu bar symbol: it has no bars to grade,
/// but it is also not the wired router the no-radio branch already draws.
final class HotspotPresentationTests: XCTestCase {
    private func data(battery: Int? = nil) -> ModemData {
        ModemData(batteryPercent: battery, isCharging: false, signalBars: 0,
                  networkType: "Wi-Fi", provider: "iPhone", rsrp: nil, sinr: nil,
                  isOnline: true, rxSpeed: 1_000, txSpeed: 500, sessionRx: nil,
                  sessionTx: nil, totalRx: 5_000, totalTx: 2_000, monthlyRx: nil,
                  monthlyTx: nil, sessionUptime: nil, monthlyUptime: nil)
    }

    func testATetheredPhoneGetsTheHotspotSymbol() {
        let p = MenuBarPresentation.make(for: .connected(data()),
                                         showsRadioSignal: false,
                                         isTether: true)
        XCTAssertEqual(p.symbolName, "personalhotspot")
        XCTAssertTrue(p.isVisible)
    }

    /// The existing no-radio branch belongs to wired routers and must keep it.
    func testAWiredRouterStillGetsTheRouterSymbol() {
        let p = MenuBarPresentation.make(for: .connected(data()),
                                         showsRadioSignal: false,
                                         isTether: false)
        XCTAssertEqual(p.symbolName, "wifi.router")
    }

    /// Zero bars means "no signal" for a modem, but a tether has no bars at
    /// all — it must not fall into the no-signal branch.
    func testZeroBarsDoNotMakeATetherLookDisconnected() {
        let p = MenuBarPresentation.make(for: .connected(data()),
                                         showsRadioSignal: false,
                                         isTether: true)
        XCTAssertNotEqual(p.symbolName, "antenna.radiowaves.left.and.right.slash")
    }

    /// No battery reading exists, so the percentage preference has nothing to
    /// render even when the user has it switched on.
    func testNoBatteryTextEvenWhenThePreferenceIsOn() {
        let p = MenuBarPresentation.make(for: .connected(data(battery: nil)),
                                         showBatteryPercent: true,
                                         showsRadioSignal: false,
                                         isTether: true)
        XCTAssertNil(p.batteryText)
    }
}
