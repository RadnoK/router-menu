import XCTest
@testable import ZteMenu

private struct FixedSSID: SSIDReading {
    let value: String?
    func currentSSID() -> String? { value }
}
private struct FixedReach: ReachabilityChecking {
    let ok: Bool
    func isReachable(_ url: URL) async -> Bool { ok }
}

final class NetworkDetectorTests: XCTestCase {
    private let url = URL(string: "http://192.168.0.1")!

    func testBySSIDMatch() async {
        let d = NetworkDetector(reader: FixedSSID(value: "ZTE_B4B622"), reachability: FixedReach(ok: false))
        let r = await d.isOnTarget(mode: .bySSID, ssid: "ZTE_B4B622", modemURL: url)
        XCTAssertTrue(r)
    }

    func testBySSIDNoMatch() async {
        let d = NetworkDetector(reader: FixedSSID(value: "Inne"), reachability: FixedReach(ok: true))
        let r = await d.isOnTarget(mode: .bySSID, ssid: "ZTE_B4B622", modemURL: url)
        XCTAssertFalse(r)
    }

    func testByIPReachable() async {
        let d = NetworkDetector(reader: FixedSSID(value: nil), reachability: FixedReach(ok: true))
        let r = await d.isOnTarget(mode: .byIPReachable, ssid: "cokolwiek", modemURL: url)
        XCTAssertTrue(r)
    }

    func testByIPUnreachable() async {
        let d = NetworkDetector(reader: FixedSSID(value: "ZTE_B4B622"), reachability: FixedReach(ok: false))
        let r = await d.isOnTarget(mode: .byIPReachable, ssid: "ZTE_B4B622", modemURL: url)
        XCTAssertFalse(r)
    }
}
