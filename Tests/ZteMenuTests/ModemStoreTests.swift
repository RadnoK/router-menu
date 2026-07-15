import XCTest
@testable import ZteMenu

@MainActor
final class ModemStoreV2Tests: XCTestCase {
    private func makeStore(reachable: Bool, throwing: Error? = nil, history: HistoryStore) -> ModemStore {
        let defaults = UserDefaults(suiteName: "t-\(UUID().uuidString)")!
        let settings = SettingsStore(defaults: defaults)
        settings.settings.networkMode = .byIPReachable
        let detector = NetworkDetector(reader: FixedSSID(value: nil), reachability: FixedReach(ok: reachable))
        let json = Data(#"{"battery_value":"55","signalbar":"5","network_type":"ENDC","total_rx_bytes":"1000","total_tx_bytes":"500"}"#.utf8)
        let factory: @MainActor (URL, String?) -> ModemClient = { url, pass in
            let http: any HTTPFetching = throwing != nil ? ThrowingHTTP(error: throwing!) : SequenceHTTP([json])
            return ModemClient(baseURL: url, http: http, password: pass)
        }
        return ModemStore(settings: settings, history: history, detector: detector, clientFactory: factory)
    }

    func testConnectedAddsHistorySample() async {
        let hist = HistoryStore(fileURL: FileManager.default.temporaryDirectory.appendingPathComponent("h-\(UUID()).json"),
                                now: { Date(timeIntervalSince1970: 100) })
        let store = makeStore(reachable: true, history: hist)
        await store.refresh()
        if case .connected(let d) = store.state {
            XCTAssertEqual(d.batteryPercent, 55)
        } else { XCTFail("oczekiwano connected") }
        XCTAssertEqual(hist.samples.count, 1)
        XCTAssertEqual(hist.samples.last?.totalBytes, 1500)
    }

    func testUnreachableIsHidden() async {
        let hist = HistoryStore(fileURL: FileManager.default.temporaryDirectory.appendingPathComponent("h-\(UUID()).json"))
        let store = makeStore(reachable: false, history: hist)
        await store.refresh()
        XCTAssertEqual(store.state, .hidden)
        XCTAssertTrue(hist.samples.isEmpty)
    }
}

private final class SequenceHTTP: HTTPFetching, @unchecked Sendable {
    private let responses: [Data]
    private var i = 0
    init(_ responses: [Data]) { self.responses = responses }
    func data(for request: URLRequest) async throws -> Data {
        defer { i += 1 }
        return responses[min(i, responses.count - 1)]
    }
}
private struct ThrowingHTTP: HTTPFetching {
    let error: Error
    func data(for request: URLRequest) async throws -> Data { throw error }
}
private struct FixedSSID: SSIDReading { let value: String?; func currentSSID() -> String? { value } }
private struct FixedReach: ReachabilityChecking { let ok: Bool; func isReachable(_ url: URL) async -> Bool { ok } }
