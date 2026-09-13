import XCTest
@testable import RouterMenu

/// Mirrors the fixture in the other store tests, which keep theirs `private`.
private struct FixedSSID: SSIDReading {
    let value: String?
    func currentSSID() -> String? { value }
}

@MainActor
final class WidgetPublishingTests: XCTestCase {
    private nonisolated static let json = Data(#"{"battery_value":"55","signalbar":"5","network_type":"ENDC","total_rx_bytes":"1000","total_tx_bytes":"500","Z5g_rsrp":"-95","Z5g_SINR":"12"}"#.utf8)

    private struct FakeDriver: ModemDriving {
        var reachable = false
        var error: Error?
        func fetch() async throws -> ModemData {
            if let error { throw error }
            return ZTEClient.parse(try JSONDecoder()
                .decode([String: String].self, from: WidgetPublishingTests.json))
        }
        func probe() async -> Bool { reachable }
    }

    private final class SpyPublisher: WidgetPublishing {
        var published: [WidgetSnapshot] = []
        var clearCount = 0
        func publish(_ snapshot: WidgetSnapshot) { published.append(snapshot) }
        func clear() { clearCount += 1 }
    }

    private func makeStore(reachable: Bool,
                           throwing: Error? = nil,
                           history: HistoryStore,
                           publisher: SpyPublisher) -> ModemStore {
        let defaults = UserDefaults(suiteName: "w-\(UUID().uuidString)")!
        let settings = SettingsStore(defaults: defaults)
        settings.profile.matchMode = .ipProbe
        settings.profile.name = "Test Modem"
        let store = ModemStore(settings: settings, history: history,
                               matcher: ModemMatcher(reader: FixedSSID(value: nil)),
                               driverFactory: { _ in
                                   FakeDriver(reachable: reachable, error: throwing)
                               })
        store.setWidgetPublisher(publisher)
        return store
    }

    private func tempHistory() -> HistoryStore {
        HistoryStore(fileURL: FileManager.default.temporaryDirectory
                        .appendingPathComponent("wh-\(UUID()).json"),
                     now: { Date(timeIntervalSince1970: 100) })
    }

    /// `profile.name` is empty until the user types a custom label, so
    /// publishing it left the widget with a blank device name.
    func testUnnamedProfileStillPublishesADeviceName() async {
        let spy = SpyPublisher()
        let defaults = UserDefaults(suiteName: "w-\(UUID().uuidString)")!
        let settings = SettingsStore(defaults: defaults)
        settings.profile.matchMode = .ipProbe
        settings.profile.name = ""
        let store = ModemStore(settings: settings, history: tempHistory(),
                               matcher: ModemMatcher(reader: FixedSSID(value: nil)),
                               driverFactory: { _ in FakeDriver(reachable: true) })
        store.setWidgetPublisher(spy)
        await store.refresh()
        let published = spy.published.first?.deviceName ?? ""
        XCTAssertFalse(published.isEmpty, "widget would show a blank device")
    }

    func testConnectedPublishesTheReading() async {
        let spy = SpyPublisher()
        let store = makeStore(reachable: true, history: tempHistory(), publisher: spy)
        await store.refresh()
        XCTAssertEqual(spy.published.count, 1)
        XCTAssertEqual(spy.published.first?.batteryPercent, 55)
        XCTAssertEqual(spy.published.first?.networkLabel, "5G")
        XCTAssertEqual(spy.published.first?.deviceName, "Test Modem")
        XCTAssertEqual(spy.clearCount, 0)
    }

    /// The published series must already contain the reading being published,
    /// or the widget's chart trails its own headline number by one tick.
    func testPublishedHistoryIncludesTheCurrentReading() async {
        let spy = SpyPublisher()
        let store = makeStore(reachable: true, history: tempHistory(), publisher: spy)
        await store.refresh()
        XCTAssertEqual(spy.published.first?.batteryHistory.last?.v, 55)
    }

    func testNoMatchClearsTheWidget() async {
        let spy = SpyPublisher()
        let store = makeStore(reachable: false, history: tempHistory(), publisher: spy)
        await store.refresh()
        XCTAssertTrue(spy.published.isEmpty)
        XCTAssertEqual(spy.clearCount, 1)
    }

    /// An unreachable modem must not leave the last good reading on screen —
    /// the widget would keep presenting it as the current state.
    func testUnreachableModemClearsTheWidget() async {
        let spy = SpyPublisher()
        // Anything that is not `loginFailed` lands in the unreachable branch.
        let store = makeStore(reachable: true, throwing: URLError(.timedOut),
                              history: tempHistory(), publisher: spy)
        await store.refresh()
        XCTAssertTrue(spy.published.isEmpty)
        XCTAssertEqual(spy.clearCount, 1)
    }

    func testLoginFailureClearsTheWidget() async {
        let spy = SpyPublisher()
        let store = makeStore(reachable: true, throwing: ModemError.loginFailed,
                              history: tempHistory(), publisher: spy)
        await store.refresh()
        XCTAssertEqual(spy.clearCount, 1)
    }

    /// A store with no publisher is the test and pre-wiring case; it must not trap.
    func testStoreWithoutAPublisherRefreshesNormally() async {
        let defaults = UserDefaults(suiteName: "w-\(UUID().uuidString)")!
        let settings = SettingsStore(defaults: defaults)
        settings.profile.matchMode = .ipProbe
        let store = ModemStore(settings: settings, history: tempHistory(),
                               matcher: ModemMatcher(reader: FixedSSID(value: nil)),
                               driverFactory: { _ in FakeDriver(reachable: true) })
        await store.refresh()
        guard case .connected = store.state else { return XCTFail("expected connected") }
    }
}

final class WidgetReloadBudgetTests: XCTestCase {
    private func make(battery: Int? = 80, charging: Bool = false, bars: Int = 3,
                      network: String = "5G", online: Bool = true,
                      device: String = "ZTE", rx: Int? = 10) -> WidgetSnapshot {
        WidgetSnapshot(capturedAt: Date(), deviceName: device, batteryPercent: battery,
                       isCharging: charging, signalBars: bars, networkLabel: network,
                       rsrp: -95, sinr: 12, rxSpeed: rx, txSpeed: 5,
                       sessionRx: 1, sessionTx: 2, batteryHistory: [], isOnline: online)
    }

    private func worth(_ a: WidgetSnapshot?, _ b: WidgetSnapshot) -> Bool {
        WidgetCenterPublisher.isWorthReloading(previous: a, next: b)
    }

    func testFirstSnapshotAlwaysReloads() {
        XCTAssertTrue(worth(nil, make()))
    }

    func testIdenticalReadingDoesNotReload() {
        XCTAssertFalse(worth(make(), make()))
    }

    /// Speeds move every tick; reloading on them alone would exhaust the
    /// daily refresh budget within hours.
    func testTransferSpeedAloneDoesNotReload() {
        XCTAssertFalse(worth(make(rx: 10), make(rx: 999_999)))
    }

    func testBatteryChangeReloads() {
        XCTAssertTrue(worth(make(battery: 80), make(battery: 79)))
    }

    func testChargingChangeReloads() {
        XCTAssertTrue(worth(make(charging: false), make(charging: true)))
    }

    func testSignalChangeReloads() {
        XCTAssertTrue(worth(make(bars: 3), make(bars: 4)))
    }

    func testNetworkTypeChangeReloads() {
        XCTAssertTrue(worth(make(network: "5G"), make(network: "LTE")))
    }

    func testGoingOfflineReloads() {
        XCTAssertTrue(worth(make(online: true), make(online: false)))
    }

    func testSwitchingDeviceReloads() {
        XCTAssertTrue(worth(make(device: "ZTE"), make(device: "ASUS")))
    }

    func testBatteryBecomingUnavailableReloads() {
        XCTAssertTrue(worth(make(battery: 80), make(battery: nil)))
    }
}
