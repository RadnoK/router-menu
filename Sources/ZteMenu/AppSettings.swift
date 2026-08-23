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

/// One battery level the user wants to hear about on the way down.
///
/// Carries its own identity so the notifier can track which thresholds have
/// already fired across a list the user edits freely — an index would shift
/// under a deletion and re-arm the wrong entry.
struct BatteryThreshold: Codable, Equatable, Identifiable {
    let id: UUID
    var percent: Int
    /// Urgent alerts break through Focus and use more emphatic wording.
    var isUrgent: Bool
    var isEnabled: Bool

    init(id: UUID = UUID(), percent: Int, isUrgent: Bool = false, isEnabled: Bool = true) {
        self.id = id
        self.percent = percent
        self.isUrgent = isUrgent
        self.isEnabled = isEnabled
    }
}

/// The battery alerts: a user-managed list of discharge thresholds, plus the
/// one alert that belongs to charging rather than draining.
struct BatteryNotificationSettings: Codable, Equatable {
    /// Kept sorted high to low, the order the battery meets them.
    private(set) var thresholds: [BatteryThreshold] = Self.defaultThresholds
    var fullEnabled: Bool = false

    static let defaultThresholds = [
        BatteryThreshold(percent: 20),
        BatteryThreshold(percent: 10, isUrgent: true),
    ]

    /// 1–99: a full battery is the separate `fullEnabled` alert, and a modem at
    /// 0% has already stopped reporting.
    static let percentRange = 1...99

    /// Any alert armed at all — the app only asks for notification permission
    /// once this turns true.
    var isAnyEnabled: Bool { fullEnabled || thresholds.contains(where: \.isEnabled) }

    /// - Returns: false when `percent` is out of range or already taken, so the
    ///   caller can tell the difference between "added" and "nothing happened".
    @discardableResult
    mutating func addThreshold(percent: Int, isUrgent: Bool = false) -> Bool {
        guard Self.percentRange.contains(percent),
              !thresholds.contains(where: { $0.percent == percent }) else { return false }
        thresholds.append(BatteryThreshold(percent: percent, isUrgent: isUrgent))
        sort()
        return true
    }

    mutating func removeThreshold(id: UUID) {
        thresholds.removeAll { $0.id == id }
    }

    /// Applies an edit made in the settings UI. A percentage that collides with
    /// another row is rejected rather than silently creating a duplicate that
    /// would fire two notifications for one crossing.
    @discardableResult
    mutating func updateThreshold(id: UUID, percent: Int? = nil,
                                  isUrgent: Bool? = nil, isEnabled: Bool? = nil) -> Bool {
        guard let index = thresholds.firstIndex(where: { $0.id == id }) else { return false }
        if let percent {
            guard Self.percentRange.contains(percent),
                  !thresholds.contains(where: { $0.percent == percent && $0.id != id })
            else { return false }
            thresholds[index].percent = percent
        }
        if let isUrgent { thresholds[index].isUrgent = isUrgent }
        if let isEnabled { thresholds[index].isEnabled = isEnabled }
        sort()
        return true
    }

    /// The percentage the "add" button should propose: a step below the lowest
    /// existing threshold, or a sensible starting point for an empty list.
    var suggestedNewThreshold: Int {
        guard let lowest = thresholds.map(\.percent).min() else { return 20 }
        let candidate = lowest - 5
        guard candidate >= Self.percentRange.lowerBound else {
            // Squeezed against the bottom: take any free slot instead.
            return Self.percentRange.first { p in !thresholds.contains { $0.percent == p } }
                ?? Self.percentRange.lowerBound
        }
        return candidate
    }

    private mutating func sort() {
        thresholds.sort { $0.percent > $1.percent }
    }

    /// Older versions stored a fixed low/critical pair under different keys.
    /// Those payloads decode to the defaults rather than failing, which is the
    /// same forgiving behaviour the rest of `AppSettings` relies on.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        thresholds = try c.decodeIfPresent([BatteryThreshold].self, forKey: .thresholds)
            ?? Self.defaultThresholds
        fullEnabled = try c.decodeIfPresent(Bool.self, forKey: .fullEnabled) ?? false
        sort()
    }

    init() {}
}

struct AppSettings: Codable, Equatable {
    var networkMode: NetworkMode = .bySSID
    var ssid: String = Config.targetSSID
    var modemIP: String = "192.168.0.1"
    var refreshInterval: TimeInterval = Config.refreshInterval
    var stats: StatVisibility = StatVisibility()
    var language: AppLanguage = .system
    var showBatteryPercent: Bool = false
    var showWhenDisconnected: Bool = false
    var batteryNotifications: BatteryNotificationSettings = BatteryNotificationSettings()

    static let defaults = AppSettings()

    /// Settings saved by earlier versions carry no `language`,
    /// `showBatteryPercent`, `showWhenDisconnected` or
    /// `batteryNotifications` key. Decoding each field
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
        showWhenDisconnected = try c.decodeIfPresent(Bool.self, forKey: .showWhenDisconnected) ?? d.showWhenDisconnected
        batteryNotifications = try c.decodeIfPresent(BatteryNotificationSettings.self, forKey: .batteryNotifications)
            ?? d.batteryNotifications
    }

    init() {}
}
