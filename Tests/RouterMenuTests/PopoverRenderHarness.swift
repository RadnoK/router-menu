import XCTest
import SwiftUI
@testable import RouterMenu

/// Not an assertion suite — a developer harness that renders the popover
/// offscreen and writes PNGs to /tmp/router-render/. Lets layout changes be
/// SEEN without a reachable modem, a keychain prompt, or clicking through
/// the menu bar. Run explicitly:
///     swift test --filter PopoverRenderHarness
@MainActor
final class PopoverRenderHarness: XCTestCase {
    private struct FakeDriver: ModemDriving {
        let data: ModemData
        func fetch() async throws -> ModemData { data }
        func probe() async -> Bool { true }
    }

    /// 45 minutes of believable history. Returns the final counters so the
    /// caller can hand the driver a CONSISTENT ModemData — an unrelated total
    /// would render as one absurd spike that flattens the whole chart.
    private func makeHistory(battery: Bool, rsrp: Bool) -> (HistoryStore, rx: Int, tx: Int) {
        var clock = Date(timeIntervalSince1970: 1_756_000_000)
        let store = HistoryStore(
            fileURL: FileManager.default.temporaryDirectory
                .appendingPathComponent("render-\(UUID()).json"),
            now: { clock })
        var rx = 40_000_000_000, tx = 9_000_000_000
        for i in 0..<45 {
            // A believable evening: bursts of downloading over a steady floor.
            let burst = (i % 11 < 4) ? 6_000_000 : 400_000
            rx += burst * 60 + (i * 7919) % 200_000
            tx += 150_000 * 60 + (i * 104_729) % 90_000
            store.add(battery: battery ? max(5, 82 - i / 2) : nil,
                      totalRx: rx, totalTx: tx,
                      rsrp: rsrp ? -88 - ((i * 13) % 17) : nil,
                      sinr: rsrp ? Double(9 + (i * 7) % 8) : nil)
            clock = clock.addingTimeInterval(60)
        }
        return (store, rx, tx)
    }

    private func makeStore(provider: ProviderKind, data: ModemData,
                           history: HistoryStore) async -> ModemStore {
        let defaults = UserDefaults(suiteName: "render-\(UUID().uuidString)")!
        let settings = SettingsStore(defaults: defaults)
        // Field mutations, not a whole-profile swap: the profile setter drops
        // writes whose id is not already in the list.
        settings.profile.provider = provider
        settings.profile.matchMode = .ipProbe
        settings.profile.name = provider == .zte ? "ZTE U50" : "Router Okopowa"
        let store = ModemStore(settings: settings, history: history,
                               matcher: ModemMatcher(reader: NoSSID()),
                               driverFactory: { _ in FakeDriver(data: data) })
        await store.refresh()
        return store
    }

    private func render(_ store: ModemStore, settings: SettingsStore,
                        name: String, dark: Bool) {
        // ImageRenderer, not an offscreen NSHostingView: a hosting view with
        // no backing window skips text and material layers entirely.
        // The xctest runner's main bundle has no .lproj folders — point L10n
        // at the repo's Resources directory so real strings render.
        let resources = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // RouterMenuTests
            .deletingLastPathComponent()   // Tests
            .deletingLastPathComponent()   // repo root
            .appendingPathComponent("Resources")
        let bundles = [Bundle(path: resources.path), Bundle.main].compactMap { $0 }
        let view = PopoverView(store: store, settings: settings,
                               l10n: L10n(language: .en, bundles: bundles),
                               openSettings: {})
            .environment(\.colorScheme, dark ? .dark : .light)
            // Fixed stand-ins for the popover material, which ImageRenderer
            // cannot draw outside a real window.
            .background(dark ? Color(white: 0.13) : Color(white: 0.97))
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        guard let image = renderer.nsImage,
              let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: NSBitmapImageRep.FileType.png,
                                           properties: [:]) else {
            return XCTFail("render produced no image")
        }
        let dir = URL(fileURLWithPath: "/tmp/router-render", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("\(name)-\(dark ? "dark" : "light").png")
        try? png.write(to: url)
        print("rendered \(url.path) (\(Int(image.size.width))×\(Int(image.size.height)))")
    }

    func testRenderZTEPopover() async {
        let (history, rx, tx) = makeHistory(battery: true, rsrp: true)
        let data = ModemData(batteryPercent: 61, isCharging: false, signalBars: 4,
                             networkType: "ENDC", provider: "Plus", rsrp: -93,
                             sinr: 12, isOnline: true,
                             rxSpeed: 5_871_000, txSpeed: 912_000,
                             sessionRx: 1_008_395_299, sessionTx: 350_536_546,
                             totalRx: rx + 5_871_000 * 60, totalTx: tx + 912_000 * 60,
                             monthlyRx: 20_248_857_403, monthlyTx: 3_998_344_877,
                             sessionUptime: 7100, monthlyUptime: 127_070)
        let store = await makeStore(provider: .zte, data: data, history: history)
        let settings = SettingsStore(defaults: UserDefaults(suiteName: "r-\(UUID())")!)
        settings.profile = store.activeProfile ?? settings.profile
        render(store, settings: settings, name: "zte", dark: false)
        render(store, settings: settings, name: "zte", dark: true)
    }

    func testRenderAsusPopover() async {
        let (history, rx, tx) = makeHistory(battery: false, rsrp: false)
        let data = ModemData(batteryPercent: nil, isCharging: false, signalBars: 0,
                             networkType: "DHCP", provider: nil, rsrp: nil,
                             sinr: nil, isOnline: true,
                             rxSpeed: 16_500_000, txSpeed: 121_000,
                             sessionRx: nil, sessionTx: nil,
                             totalRx: rx + 16_500_000 * 60, totalTx: tx + 121_000 * 60,
                             monthlyRx: nil, monthlyTx: nil,
                             sessionUptime: 340_000, monthlyUptime: nil)
        let store = await makeStore(provider: .asus, data: data, history: history)
        let settings = SettingsStore(defaults: UserDefaults(suiteName: "r-\(UUID())")!)
        settings.profile = store.activeProfile ?? settings.profile
        render(store, settings: settings, name: "asus", dark: false)
        render(store, settings: settings, name: "asus", dark: true)
    }
}

private struct NoSSID: SSIDReading {
    func currentSSID() -> String? { nil }
}
