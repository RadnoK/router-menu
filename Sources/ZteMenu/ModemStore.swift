import Foundation
import Observation

@MainActor
@Observable
public final class ModemStore {
    private(set) var state: AppState = .hidden
    /// The device the last refresh matched. The popover header and the menu
    /// bar label read their per-device presentation preferences from it.
    private(set) var activeProfile: ModemProfile?
    private let settings: SettingsStore
    let history: HistoryStore
    private let matcher: ModemMatcher
    private let driverFactory: @MainActor (ModemProfile) -> any ModemDriving
    private var locationAuth: LocationAuth = .authorized
    /// Optional so tests get a store that posts nothing; the app wires one in.
    private var notifier: BatteryNotifier?

    init(settings: SettingsStore,
         history: HistoryStore,
         matcher: ModemMatcher = ModemMatcher(),
         driverFactory: @escaping @MainActor (ModemProfile) -> any ModemDriving = { profile in
             ProviderCatalog.descriptor(for: profile.provider)
                 .makeDriver(profile.baseURL, Keychain.password(), SessionHTTP())
         }) {
        self.settings = settings
        self.history = history
        self.matcher = matcher
        self.driverFactory = driverFactory
    }

    func setBatteryNotifier(_ notifier: BatteryNotifier) {
        self.notifier = notifier
    }

    func setLocationAuth(_ auth: LocationAuth) {
        locationAuth = auth
    }

    func refresh() async {
        let result = await matcher.match(in: settings.settings.profiles,
                                         locationAuthorized: locationAuth != .denied,
                                         probe: { await self.driverFactory($0).probe() })
        switch result {
        case .none(ssidSkipped: true):
            activeProfile = nil
            state = .locationDenied
        case .none(ssidSkipped: false):
            activeProfile = nil
            state = .hidden
        case .matched(let profile):
            activeProfile = profile
            let driver = driverFactory(profile)
            do {
                let data = try await driver.fetch()
                state = .connected(data)
                history.add(battery: data.batteryPercent, totalBytes: data.totalBytesForHistory)
                notifier?.handle(data, profile: profile)
            } catch ModemError.loginFailed {
                state = .error(.loginFailed)
            } catch {
                state = .error(.unreachable)
            }
        }
    }
}
