import Foundation

enum NetworkMode: String, Codable, CaseIterable {
    case bySSID
    case byIPReachable
}

struct StatVisibility: Codable, Equatable {
    var basic: Bool = true
    var radio: Bool = true
    var transfer: Bool = true
    var uptime: Bool = true
}

/// Thresholds for the battery alerts, and which of them are armed at all.
///
/// Percentages, not fractions: they come straight from the modem, are shown
/// as-is in settings, and interpolate into the notification text unchanged.
struct BatteryNotificationSettings: Codable, Equatable {
    var lowEnabled: Bool = true
    var lowThreshold: Int = 20
    var criticalEnabled: Bool = true
    var criticalThreshold: Int = 10
    var fullEnabled: Bool = false

    /// Any alert armed at all — the app only asks for notification permission
    /// once this turns true.
    var isAnyEnabled: Bool { lowEnabled || criticalEnabled || fullEnabled }

    /// The range the settings steppers offer. 5–95 in steps of 5: finer control
    /// than that is noise on a reading the modem reports in whole percent.
    static let thresholdRange = 5...95
    static let thresholdStep = 5

    /// Keeps `critical` strictly below `low`, whichever one the user just moved.
    ///
    /// The steppers edit the two values independently, so without this a user
    /// raising `critical` past `low` would leave `low` unreachable — the battery
    /// would cross both at once and only the critical alert would ever fire.
    /// - Parameter movedCritical: which stepper produced the change; the other
    ///   value is the one that gives way.
    mutating func resolveThresholdOverlap(movedCritical: Bool) {
        guard criticalThreshold >= lowThreshold else { return }
        if movedCritical {
            let pushed = criticalThreshold + Self.thresholdStep
            if pushed <= Self.thresholdRange.upperBound {
                lowThreshold = pushed
            } else {
                // `low` has nowhere left to go, so `critical` gives way instead.
                criticalThreshold = lowThreshold - Self.thresholdStep
            }
        } else {
            let pushed = lowThreshold - Self.thresholdStep
            if pushed >= Self.thresholdRange.lowerBound {
                criticalThreshold = pushed
            } else {
                lowThreshold = criticalThreshold + Self.thresholdStep
            }
        }
    }
}

struct AppSettings: Codable, Equatable {
    var networkMode: NetworkMode = .bySSID
    var ssid: String = Config.targetSSID
    var modemIP: String = "192.168.0.1"
    var refreshInterval: TimeInterval = Config.refreshInterval
    var stats: StatVisibility = StatVisibility()
    var language: AppLanguage = .system
    var showBatteryPercent: Bool = false
    var batteryNotifications: BatteryNotificationSettings = BatteryNotificationSettings()

    static let defaults = AppSettings()

    /// Settings saved by earlier versions carry no `language`,
    /// `showBatteryPercent` or `batteryNotifications` key. Decoding each field
    /// individually keeps those payloads loadable instead of throwing and
    /// silently resetting every preference.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = AppSettings.defaults
        networkMode = try c.decodeIfPresent(NetworkMode.self, forKey: .networkMode) ?? d.networkMode
        ssid = try c.decodeIfPresent(String.self, forKey: .ssid) ?? d.ssid
        modemIP = try c.decodeIfPresent(String.self, forKey: .modemIP) ?? d.modemIP
        refreshInterval = try c.decodeIfPresent(TimeInterval.self, forKey: .refreshInterval) ?? d.refreshInterval
        stats = try c.decodeIfPresent(StatVisibility.self, forKey: .stats) ?? d.stats
        language = try c.decodeIfPresent(AppLanguage.self, forKey: .language) ?? .system
        showBatteryPercent = try c.decodeIfPresent(Bool.self, forKey: .showBatteryPercent) ?? d.showBatteryPercent
        batteryNotifications = try c.decodeIfPresent(BatteryNotificationSettings.self, forKey: .batteryNotifications)
            ?? d.batteryNotifications
    }

    init() {}
}
