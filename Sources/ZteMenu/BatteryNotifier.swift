import Foundation
import UserNotifications

/// What the user should be told about, if anything.
///
/// The associated percentage is the reading that triggered the alert, so the
/// notification text can quote the real level rather than the threshold.
enum BatteryAlert: Equatable {
    case low(Int)
    case critical(Int)
    case full
}

/// Decides whether a battery reading deserves a notification.
///
/// Pure state machine, deliberately separate from delivery: the refresh loop
/// hands it the same reading every 60 s, so "below the threshold" is the wrong
/// question — it must fire on the *crossing* and then stay quiet until the
/// battery genuinely recovers. Keeping it free of `UNUserNotificationCenter`
/// is what makes that rule testable.
struct BatteryAlertDecider {
    /// How far above a threshold the battery must climb before that alert is
    /// armed again. Without it, a reading hovering at the threshold would
    /// alternate between fired and re-armed and notify on every tick.
    static let hysteresis = 5

    private var lowFired = false
    private var criticalFired = false
    private var fullFired = false
    private var hasBaseline = false

    init() {}

    /// - Returns: the alert to present, or `nil` when this reading changes
    ///   nothing. At most one alert per reading; `critical` outranks `low`.
    mutating func decide(percent: Int,
                         isCharging: Bool,
                         settings: BatteryNotificationSettings) -> BatteryAlert? {
        defer { hasBaseline = true }

        if isCharging {
            // Plugged in: the level is on its way up, so a low reading is not a
            // problem. Disarming here also means unplugging later can't fire an
            // alert for a crossing that happened while charging.
            lowFired = true
            criticalFired = true
        } else {
            fullFired = false
            if percent >= settings.lowThreshold + Self.hysteresis { lowFired = false }
            if percent >= settings.criticalThreshold + Self.hysteresis { criticalFired = false }
        }

        // The first reading only tells us where the battery is, not that it
        // moved — launching next to an empty battery is not a crossing.
        guard hasBaseline else {
            if percent < settings.lowThreshold { lowFired = true }
            if percent < settings.criticalThreshold { criticalFired = true }
            if percent >= 100 { fullFired = true }
            return nil
        }

        if isCharging {
            if settings.fullEnabled, percent >= 100, !fullFired {
                fullFired = true
                return .full
            }
            return nil
        }

        if settings.criticalEnabled, percent < settings.criticalThreshold, !criticalFired {
            criticalFired = true
            // A drop past both thresholds at once reports the urgent one, but
            // must still mark `low` as spent so it can't fire on the way down.
            lowFired = true
            return .critical(percent)
        }
        if settings.lowEnabled, percent < settings.lowThreshold, !lowFired {
            lowFired = true
            return .low(percent)
        }
        return nil
    }
}

/// Delivery side of the battery alerts, kept behind a protocol so the store's
/// tests never touch the real notification centre (which needs a signed bundle
/// and would prompt the user).
@MainActor
protocol BatteryAlertPresenting: AnyObject {
    func present(_ alert: BatteryAlert)
    /// Ask for permission — called when the user arms an alert, not at launch,
    /// so the prompt arrives with the context that explains it.
    func requestAuthorization()
}

/// Watches the battery readings and posts user notifications for the alerts the
/// user armed in settings.
@MainActor
final class BatteryNotifier {
    private var decider = BatteryAlertDecider()
    private let settings: SettingsStore
    private let presenter: any BatteryAlertPresenting

    init(settings: SettingsStore, presenter: any BatteryAlertPresenting) {
        self.settings = settings
        self.presenter = presenter
    }

    convenience init(settings: SettingsStore, l10n: L10n) {
        self.init(settings: settings, presenter: UserNotificationPresenter(l10n: l10n))
    }

    func handle(_ data: ModemData) {
        let config = settings.settings.batteryNotifications
        guard let percent = data.batteryPercent else { return }
        guard let alert = decider.decide(percent: percent,
                                         isCharging: data.isCharging,
                                         settings: config) else { return }
        presenter.present(alert)
    }

    /// Called when the user turns an alert on in settings.
    func requestAuthorizationIfNeeded() {
        guard settings.settings.batteryNotifications.isAnyEnabled else { return }
        presenter.requestAuthorization()
    }
}

/// Posts the alerts through `UNUserNotificationCenter`.
@MainActor
final class UserNotificationPresenter: BatteryAlertPresenting {
    private let center = UNUserNotificationCenter.current()
    private let l10n: L10n?

    init(l10n: L10n?) { self.l10n = l10n }

    func requestAuthorization() {
        center.requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    func present(_ alert: BatteryAlert) {
        let content = UNMutableNotificationContent()
        content.title = title(for: alert)
        content.body = body(for: alert)
        content.sound = .default
        // No trigger: deliver now. The identifier is unique per post so a new
        // alert never replaces one the user has not seen yet.
        let request = UNNotificationRequest(identifier: "battery-\(UUID().uuidString)",
                                            content: content,
                                            trigger: nil)
        center.add(request) { _ in }
    }

    /// Falls back to the raw key when no `L10n` was injected, matching how the
    /// rest of the app degrades on a missing string.
    private func string(_ key: LocKey) -> String {
        l10n.map { $0(key) } ?? key.rawValue
    }

    private func string(_ key: LocKey, percent: Int) -> String {
        l10n.map { $0(key, percent) } ?? key.rawValue
    }

    private func title(for alert: BatteryAlert) -> String {
        switch alert {
        case .low: return string(.notificationBatteryLowTitle)
        case .critical: return string(.notificationBatteryCriticalTitle)
        case .full: return string(.notificationBatteryFullTitle)
        }
    }

    private func body(for alert: BatteryAlert) -> String {
        switch alert {
        case .low(let p): return string(.notificationBatteryLowBody, percent: p)
        case .critical(let p): return string(.notificationBatteryCriticalBody, percent: p)
        case .full: return string(.notificationBatteryFullBody)
        }
    }
}
