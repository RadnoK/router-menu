import Foundation
import UserNotifications

/// What the user should be told about, if anything.
///
/// The associated percentage is the reading that triggered the alert, so the
/// notification text can quote the real level rather than the threshold.
enum BatteryAlert: Equatable {
    case threshold(percent: Int, isUrgent: Bool)
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

    /// Thresholds that have already fired and are waiting for the battery to
    /// recover. Keyed by identity, not by percentage, so editing a row in
    /// settings doesn't hand its "already fired" state to a different entry.
    private var firedThresholds: Set<UUID> = []
    private var fullFired = false
    private var hasBaseline = false

    init() {}

    /// - Returns: the alert to present, or `nil` when this reading changes
    ///   nothing. At most one alert per reading: a drop past several thresholds
    ///   at once reports the lowest one crossed, which is the most urgent news.
    mutating func decide(percent: Int,
                         isCharging: Bool,
                         settings: BatteryNotificationSettings) -> BatteryAlert? {
        defer { hasBaseline = true }
        let crossed = settings.thresholds.filter { percent < $0.percent }

        if isCharging {
            // Plugged in: the level is on its way up, so a low reading is not a
            // problem. Marking the crossings as spent also means unplugging
            // later can't fire an alert for a drop that happened while charging.
            firedThresholds.formUnion(crossed.map(\.id))
        } else {
            fullFired = false
            for threshold in settings.thresholds
            where percent >= threshold.percent + Self.hysteresis {
                firedThresholds.remove(threshold.id)
            }
        }

        // The first reading only tells us where the battery is, not that it
        // moved — launching next to an empty battery is not a crossing.
        guard hasBaseline else {
            firedThresholds.formUnion(crossed.map(\.id))
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

        // Lowest first: that is the one worth interrupting for, and every other
        // threshold crossed by the same drop is marked spent alongside it.
        let fresh = crossed
            .filter { !firedThresholds.contains($0.id) }
            .sorted { $0.percent < $1.percent }
        guard !fresh.isEmpty else { return nil }
        firedThresholds.formUnion(fresh.map(\.id))

        guard let alert = fresh.first(where: \.isEnabled) else { return nil }
        return .threshold(percent: percent, isUrgent: alert.isUrgent)
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
        if case .threshold(_, isUrgent: true) = alert {
            // Breaks through Focus: the user marked this level as one they do
            // not want to miss.
            content.interruptionLevel = .timeSensitive
        }
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
        case .threshold(_, let isUrgent):
            return string(isUrgent ? .notificationBatteryCriticalTitle : .notificationBatteryLowTitle)
        case .full:
            return string(.notificationBatteryFullTitle)
        }
    }

    private func body(for alert: BatteryAlert) -> String {
        switch alert {
        case .threshold(let p, let isUrgent):
            return string(isUrgent ? .notificationBatteryCriticalBody : .notificationBatteryLowBody,
                          percent: p)
        case .full:
            return string(.notificationBatteryFullBody)
        }
    }
}
