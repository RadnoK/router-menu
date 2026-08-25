import XCTest
@testable import RouterMenu

@MainActor
final class ModemStoreV2Tests: XCTestCase {
    private nonisolated static let json = Data(#"{"battery_value":"55","signalbar":"5","network_type":"ENDC","total_rx_bytes":"1000","total_tx_bytes":"500","Z5g_rsrp":"-95","Z5g_SINR":"12"}"#.utf8)

    private struct FakeDriver: ModemDriving {
        var reachable = false
        var error: Error?
        func fetch() async throws -> ModemData {
            if let error { throw error }
            return ZTEClient.parse(try JSONDecoder()
                .decode([String: String].self, from: ModemStoreV2Tests.json))
        }
        func probe() async -> Bool { reachable }
    }

    private func makeStore(mode: MatchMode,
                           currentSSID: String? = nil,
                           reachable: Bool = false,
                           throwing: Error? = nil,
                           history: HistoryStore) -> ModemStore {
        let defaults = UserDefaults(suiteName: "t-\(UUID().uuidString)")!
        let settings = SettingsStore(defaults: defaults)
        settings.profile.matchMode = mode
        settings.profile.ssid = "ZTE_B4B622"
        let matcher = ModemMatcher(reader: FixedSSID(value: currentSSID))
        return ModemStore(settings: settings, history: history, matcher: matcher,
                          driverFactory: { _ in FakeDriver(reachable: reachable, error: throwing) })
    }

    private func tempHistory() -> HistoryStore {
        HistoryStore(fileURL: FileManager.default.temporaryDirectory
                        .appendingPathComponent("h-\(UUID()).json"),
                     now: { Date(timeIntervalSince1970: 100) })
    }

    func testConnectedPublishesTheMatchedProfileAndAddsHistory() async {
        let hist = tempHistory()
        let store = makeStore(mode: .ipProbe, reachable: true, history: hist)
        await store.refresh()
        if case .connected(let d) = store.state {
            XCTAssertEqual(d.batteryPercent, 55)
        } else { XCTFail("expected connected, got \(store.state)") }
        XCTAssertEqual(store.activeProfile?.matchMode, .ipProbe)
        XCTAssertEqual(hist.samples.count, 1)
        XCTAssertEqual(hist.samples.last?.totalBytes, 1500)
        XCTAssertEqual(hist.samples.last?.totalRx, 1000)
        XCTAssertEqual(hist.samples.last?.totalTx, 500)
        XCTAssertEqual(hist.samples.last?.rsrp, -95)
        XCTAssertEqual(hist.samples.last?.sinr, 12)
    }

    func testSSIDMatchConnects() async {
        let store = makeStore(mode: .ssid, currentSSID: "ZTE_B4B622",
                              reachable: false, history: tempHistory())
        await store.refresh()
        guard case .connected = store.state else {
            return XCTFail("expected connected, got \(store.state)")
        }
    }

    func testNoMatchHidesAndClearsTheProfile() async {
        let hist = tempHistory()
        let store = makeStore(mode: .ipProbe, reachable: false, history: hist)
        await store.refresh()
        XCTAssertEqual(store.state, .hidden)
        XCTAssertNil(store.activeProfile)
        XCTAssertTrue(hist.samples.isEmpty)
    }

    func testDeniedLocationWithSSIDProfileIsLocationDenied() async {
        let store = makeStore(mode: .ssid, currentSSID: "ZTE_B4B622", history: tempHistory())
        store.setLocationAuth(.denied)
        await store.refresh()
        XCTAssertEqual(store.state, .locationDenied)
        XCTAssertNil(store.activeProfile)
    }

    func testDeniedLocationStillConnectsThroughAnIPProfile() async {
        // The behavioural refinement this refactor buys: location only gates
        // SSID matching, not the whole app.
        let store = makeStore(mode: .ipProbe, reachable: true, history: tempHistory())
        store.setLocationAuth(.denied)
        await store.refresh()
        guard case .connected = store.state else {
            return XCTFail("expected connected, got \(store.state)")
        }
    }

    func testLoginFailureMapsToError() async {
        let store = makeStore(mode: .ipProbe, reachable: true,
                              throwing: ModemError.loginFailed, history: tempHistory())
        await store.refresh()
        XCTAssertEqual(store.state, .error(.loginFailed))
    }

    func testOtherFetchFailureMapsToUnreachable() async {
        struct Boom: Error {}
        let store = makeStore(mode: .ipProbe, reachable: true,
                              throwing: Boom(), history: tempHistory())
        await store.refresh()
        XCTAssertEqual(store.state, .error(.unreachable))
    }

    func testDeviceSwitchBreaksTheTransferDiffChain() async {
        let hist = tempHistory()
        let defaults = UserDefaults(suiteName: "t-\(UUID().uuidString)")!
        let settings = SettingsStore(defaults: defaults)
        settings.profile.matchMode = .ssid
        settings.profile.ssid = "ZTE_B4B622"
        let asusID = settings.settings.addProfile(provider: .asus)
        let matcher = ModemMatcher(reader: FixedSSID(value: "ZTE_B4B622"))
        let store = ModemStore(settings: settings, history: hist, matcher: matcher,
                               driverFactory: { _ in FakeDriver(reachable: true) })

        await store.refresh()   // matches the ZTE profile (SSID)
        // Stop the SSID from matching so the ipProbe Asus profile wins next.
        settings.profile.ssid = "SomewhereElse"
        _ = asusID
        await store.refresh()   // matches the Asus profile
        await store.refresh()   // Asus again — same device as last sample

        XCTAssertEqual(hist.samples.count, 3)
        XCTAssertNotNil(hist.samples[0].totalBytes, "first device's first sample carries totals")
        XCTAssertNil(hist.samples[1].totalBytes, "device boundary must break the diff chain")
        XCTAssertNotNil(hist.samples[2].totalBytes, "same device again — chain resumes")
    }
}

private struct FixedSSID: SSIDReading {
    let value: String?
    func currentSSID() -> String? { value }
}
