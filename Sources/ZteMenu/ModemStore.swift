import Foundation
import Observation

@MainActor
@Observable
final class ModemStore {
    private(set) var state: AppState = .hidden
    private let monitor: WiFiMonitor
    private let client: ModemClient
    private var locationAuth: LocationAuth = .authorized

    init(monitor: WiFiMonitor = WiFiMonitor(), client: ModemClient = ModemClient()) {
        self.monitor = monitor
        self.client = client
    }

    func setLocationAuth(_ auth: LocationAuth) {
        locationAuth = auth
    }

    func refresh() async {
        // Bez zgody na lokalizację odczyt SSID jest niewiarygodny.
        if locationAuth == .denied {
            state = .locationDenied
            return
        }
        guard monitor.isOnTargetNetwork else {
            state = .hidden
            return
        }
        do {
            let data = try await client.fetch()
            state = .connected(data)
        } catch {
            state = .error("Nie można połączyć z modemem")
        }
    }
}
