import Foundation
import Observation

@MainActor
@Observable
public final class ModemStore {
    private(set) var state: AppState = .hidden
    private let settings: SettingsStore
    let history: HistoryStore
    private let detector: NetworkDetector
    private let clientFactory: @MainActor (URL, String?) -> ModemClient
    private var locationAuth: LocationAuth = .authorized
    /// Optional so tests get a store that posts nothing; the app wires one in.
    private var notifier: BatteryNotifier?

    public init(settings: SettingsStore,
                history: HistoryStore,
                detector: NetworkDetector = NetworkDetector(),
                clientFactory: @escaping @MainActor (URL, String?) -> ModemClient = { url, pass in
                    ModemClient(baseURL: url, http: SessionHTTP(), password: pass)
                }) {
        self.settings = settings
        self.history = history
        self.detector = detector
        self.clientFactory = clientFactory
    }

    func setBatteryNotifier(_ notifier: BatteryNotifier) {
        self.notifier = notifier
    }

    func setLocationAuth(_ auth: LocationAuth) {
        locationAuth = auth
    }

    func refresh() async {
        let s = settings.settings
        if s.networkMode == .bySSID && locationAuth == .denied {
            state = .locationDenied
            return
        }
        let onTarget = await detector.isOnTarget(mode: s.networkMode, ssid: s.ssid, modemURL: settings.modemBaseURL)
        guard onTarget else {
            state = .hidden
            return
        }
        let client = clientFactory(settings.modemBaseURL, Keychain.password())
        do {
            let data = try await client.fetch()
            state = .connected(data)
            history.add(battery: data.batteryPercent, totalBytes: data.totalBytesForHistory)
            notifier?.handle(data)
        } catch ModemError.loginFailed {
            state = .error(.loginFailed)
        } catch {
            state = .error(.unreachable)
        }
    }
}
