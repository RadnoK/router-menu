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
    /// Optional for the same reason: a test store must not reach into WidgetKit.
    private var widgets: (any WidgetPublishing)?
    /// Which device produced the previous history sample. Totals from two
    /// different devices must never be diffed into a transfer-speed point.
    private var lastSampledProfileID: UUID?

    init(settings: SettingsStore,
         history: HistoryStore,
         matcher: ModemMatcher = ModemMatcher(),
         driverFactory: @escaping @MainActor (ModemProfile) -> any ModemDriving = { profile in
             ProviderCatalog.descriptor(for: profile.provider)
                 .makeDriver(profile, Keychain.password(for: profile.id), SessionHTTP())
         }) {
        self.settings = settings
        self.history = history
        self.matcher = matcher
        self.driverFactory = driverFactory
    }

    func setBatteryNotifier(_ notifier: BatteryNotifier) {
        self.notifier = notifier
    }

    func setWidgetPublisher(_ widgets: any WidgetPublishing) {
        self.widgets = widgets
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
            widgets?.clear()
        case .none(ssidSkipped: false):
            activeProfile = nil
            state = .hidden
            widgets?.clear()
        case .matched(let profile):
            activeProfile = profile
            let driver = driverFactory(profile)
            do {
                let data = try await driver.fetch()
                state = .connected(data)
                // No prior sample at all is not a device boundary — only a
                // *different* previous device must break the diff chain.
                let sameDeviceAsLastSample = lastSampledProfileID == nil
                    || lastSampledProfileID == profile.id
                history.add(battery: data.batteryPercent,
                            totalRx: sameDeviceAsLastSample ? data.totalRx : nil,
                            totalTx: sameDeviceAsLastSample ? data.totalTx : nil,
                            rsrp: data.rsrp,
                            sinr: data.sinr)
                lastSampledProfileID = profile.id
                notifier?.handle(data, profile: profile)
                // After `history.add`, so the chart series the widget carries
                // includes the reading being published rather than lagging it.
                widgets?.publish(WidgetSnapshotBuilder.make(from: data,
                                                            profile: profile,
                                                            history: history))
            } catch ModemError.loginFailed {
                state = .error(.loginFailed)
                widgets?.clear()
            } catch {
                state = .error(.unreachable)
                widgets?.clear()
            }
        }
    }
}
