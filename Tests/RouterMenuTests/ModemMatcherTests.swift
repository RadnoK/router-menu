import XCTest
@testable import RouterMenu

private struct FixedSSID: SSIDReading {
    let value: String?
    func currentSSID() -> String? { value }
}

@MainActor
final class ModemMatcherTests: XCTestCase {
    private func profile(_ mode: MatchMode, ssid: String = "ZTE_B4B622",
                         ip: String = "192.168.0.1") -> ModemProfile {
        ModemProfile(provider: .zte, matchMode: mode, ssid: ssid, modemIP: ip)
    }

    func testSSIDMatch() async {
        let target = profile(.ssid)
        let m = ModemMatcher(reader: FixedSSID(value: "ZTE_B4B622"))
        let r = await m.match(in: [target], locationAuthorized: true) { _ in false }
        guard case .matched(let p) = r else { return XCTFail("expected a match") }
        XCTAssertEqual(p.id, target.id)
    }

    func testSSIDMismatchAndNoWiFiDoNotMatch() async {
        for current in ["SomeOtherNetwork", nil] {
            let m = ModemMatcher(reader: FixedSSID(value: current))
            let r = await m.match(in: [profile(.ssid)], locationAuthorized: true) { _ in false }
            XCTAssertEqual(r, .none(ssidSkipped: false))
        }
    }

    func testProbeMatchAsksTheProfileDriver() async {
        let m = ModemMatcher(reader: FixedSSID(value: nil))
        var probed: [String] = []
        let r = await m.match(in: [profile(.ipProbe, ip: "10.0.0.1")],
                              locationAuthorized: true) { p in
            probed.append(p.modemIP)
            return true
        }
        XCTAssertEqual(probed, ["10.0.0.1"])
        guard case .matched(let p) = r else { return XCTFail("expected a match") }
        XCTAssertEqual(p.modemIP, "10.0.0.1")
    }

    func testFirstMatchWins() async {
        let first = profile(.ssid, ssid: "Shared")
        let second = profile(.ssid, ssid: "Shared")
        let m = ModemMatcher(reader: FixedSSID(value: "Shared"))
        let r = await m.match(in: [first, second], locationAuthorized: true) { _ in false }
        guard case .matched(let p) = r else { return XCTFail("expected a match") }
        XCTAssertEqual(p.id, first.id)
    }

    func testDeniedLocationSkipsSSIDProfilesAndReportsIt() async {
        let m = ModemMatcher(reader: FixedSSID(value: "ZTE_B4B622"))
        let r = await m.match(in: [profile(.ssid)], locationAuthorized: false) { _ in false }
        XCTAssertEqual(r, .none(ssidSkipped: true))
    }

    func testDeniedLocationStillProbesIPProfiles() async {
        // The refinement over the old behaviour: a denied permission only
        // blocks SSID matching, not the whole app.
        let m = ModemMatcher(reader: FixedSSID(value: nil))
        let r = await m.match(in: [profile(.ssid), profile(.ipProbe)],
                              locationAuthorized: false) { _ in true }
        guard case .matched(let p) = r else { return XCTFail("expected the ip profile") }
        XCTAssertEqual(p.matchMode, .ipProbe)
    }

    func testNothingConfiguredMeansNoMatchNoSkip() async {
        let m = ModemMatcher(reader: FixedSSID(value: "Anything"))
        let r = await m.match(in: [], locationAuthorized: true) { _ in true }
        XCTAssertEqual(r, .none(ssidSkipped: false))
    }
}
