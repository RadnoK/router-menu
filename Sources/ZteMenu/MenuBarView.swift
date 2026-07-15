import SwiftUI

public struct MenuBarView: View {
    @State private var store: ModemStore

    public init(store: ModemStore = ModemStore(settings: SettingsStore(), history: HistoryStore())) {
        _store = State(initialValue: store)
    }

    public var body: some View {
        content
    }

    @ViewBuilder
    private var content: some View {
        switch store.state {
        case .hidden:
            Label("Brak połączenia z ZTE_B4B622", systemImage: "wifi.slash")
            Divider()
            Button("Zakończ") { NSApplication.shared.terminate(nil) }
        case .locationDenied:
            Label("Włącz uprawnienia lokalizacji, aby wykrywać sieć WiFi",
                  systemImage: "location.slash")
            Divider()
            Button("Zakończ") { NSApplication.shared.terminate(nil) }
        case .error(let msg):
            Label(msg, systemImage: "exclamationmark.triangle")
            Divider()
            Button("Odśwież teraz") { Task { await store.refresh() } }
            Button("Zakończ") { NSApplication.shared.terminate(nil) }
        case .connected(let d):
            connectedMenu(d)
        }
    }

    @ViewBuilder
    private func connectedMenu(_ d: ModemData) -> some View {
        Label("ZTE U50 · \(Config.targetSSID)", systemImage: "simcard")
        Divider()
        if let b = d.batteryPercent {
            Label("Bateria: \(b)%\(d.isCharging ? " (ładowanie)" : "")",
                  systemImage: batterySymbol(percent: b, charging: d.isCharging))
        }
        Label("Sygnał: \(d.signalDescription) (\(d.signalBars)/5)", systemImage: "cellularbars")
        Label("Sieć: \(d.networkLabel)", systemImage: "antenna.radiowaves.left.and.right")
        if let r = d.rsrp {
            Label("RSRP: \(r) dBm", systemImage: "waveform.path")
        }
        if let s = d.sinr {
            Label("SINR: \(String(format: "%.0f", s)) dB", systemImage: "waveform")
        }
        if let p = d.provider {
            Label("Operator: \(p)", systemImage: "network")
        }
        Divider()
        Button("Odśwież teraz") { Task { await store.refresh() } }
        Button("Zakończ") { NSApplication.shared.terminate(nil) }
    }

    /// Dobiera SF Symbol baterii wg poziomu naładowania i stanu ładowania.
    private func batterySymbol(percent: Int, charging: Bool) -> String {
        if charging { return "battery.100.bolt" }
        switch percent {
        case ...10: return "battery.0"
        case ...35: return "battery.25"
        case ...60: return "battery.50"
        case ...85: return "battery.75"
        default: return "battery.100"
        }
    }
}
