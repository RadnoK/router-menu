import SwiftUI

public struct MenuBarView: View {
    @State private var store: ModemStore
    @State private var permission = LocationPermission()

    public init(store: ModemStore = ModemStore()) {
        _store = State(initialValue: store)
    }

    public var body: some View {
        content
            .task {
                permission.onChange = { auth in store.setLocationAuth(auth) }
                store.setLocationAuth(permission.status)
                permission.requestIfNeeded()
                await store.refresh()
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(Config.refreshInterval))
                    await store.refresh()
                }
            }
    }

    @ViewBuilder
    private var content: some View {
        switch store.state {
        case .hidden:
            Text("Brak połączenia z ZTE_B4B622")
            Divider()
            Button("Zakończ") { NSApplication.shared.terminate(nil) }
        case .locationDenied:
            Text("⚠️ Włącz uprawnienia lokalizacji, aby wykrywać sieć WiFi")
            Divider()
            Button("Zakończ") { NSApplication.shared.terminate(nil) }
        case .error(let msg):
            Text("⚠️ \(msg)")
            Divider()
            Button("Odśwież teraz") { Task { await store.refresh() } }
            Button("Zakończ") { NSApplication.shared.terminate(nil) }
        case .connected(let d):
            connectedMenu(d)
        }
    }

    @ViewBuilder
    private func connectedMenu(_ d: ModemData) -> some View {
        Text("ZTE U50 · \(Config.targetSSID)")
        Divider()
        if let b = d.batteryPercent {
            Text("🔋 Bateria: \(b)%\(d.isCharging ? " (ładowanie)" : "")")
        }
        Text("📶 Sygnał: \(d.signalDescription) (\(d.signalBars)/5)")
        Text("📡 Sieć: \(d.networkLabel)")
        if let r = d.rsrp { Text("📊 RSRP: \(r) dBm") }
        if let s = d.sinr { Text("📊 SINR: \(String(format: "%.0f", s)) dB") }
        if let p = d.provider { Text("🏢 Operator: \(p)") }
        Divider()
        Button("Odśwież teraz") { Task { await store.refresh() } }
        Button("Zakończ") { NSApplication.shared.terminate(nil) }
    }
}
