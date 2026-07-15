import XCTest
@testable import ZteMenu

private struct FixedSSID: SSIDReading {
    let value: String?
    func currentSSID() -> String? { value }
}
private struct StubHTTP: HTTPFetching {
    let payload: Data
    let shouldThrow: Bool
    func data(for request: URLRequest) async throws -> Data {
        if shouldThrow { throw URLError(.cannotConnectToHost) }
        return payload
    }
}

@MainActor
final class ModemStoreTests: XCTestCase {
    private let goodJSON = Data(#"{"signalbar":"5","battery_value":"60","battery_charging":"0","network_type":"ENDC","ppp_status":"ppp_connected"}"#.utf8)

    private func makeStore(ssid: String?, throwing: Bool = false) -> ModemStore {
        let monitor = WiFiMonitor(targetSSID: "ZTE_B4B622", reader: FixedSSID(value: ssid))
        let client = ModemClient(baseURL: Config.modemBaseURL,
                                 http: StubHTTP(payload: goodJSON, shouldThrow: throwing))
        return ModemStore(monitor: monitor, client: client)
    }

    func testHiddenWhenOffNetwork() async {
        let store = makeStore(ssid: "Inne")
        await store.refresh()
        XCTAssertEqual(store.state, .hidden)
    }

    func testConnectedWhenOnNetwork() async {
        let store = makeStore(ssid: "ZTE_B4B622")
        await store.refresh()
        if case .connected(let d) = store.state {
            XCTAssertEqual(d.batteryPercent, 60)
        } else {
            XCTFail("Oczekiwano connected, było \(store.state)")
        }
    }

    func testErrorWhenModemUnreachable() async {
        let store = makeStore(ssid: "ZTE_B4B622", throwing: true)
        await store.refresh()
        if case .error = store.state {} else {
            XCTFail("Oczekiwano error, było \(store.state)")
        }
    }

    func testLocationDeniedOverridesToDeniedWhenOnNetwork() async {
        let store = makeStore(ssid: "ZTE_B4B622")
        store.setLocationAuth(.denied)
        await store.refresh()
        // Bez zgody nie da się potwierdzić SSID — traktujemy jak locationDenied.
        XCTAssertEqual(store.state, .locationDenied)
    }
}
