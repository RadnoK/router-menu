import Foundation

struct StatVisibility: Codable, Equatable {
    var basic: Bool = true
    var radio: Bool = true
    var transfer: Bool = true
    var uptime: Bool = true
    /// The session data counters row (devices that report them).
    var session: Bool = true
    // Chart toggles, one per popover chart. Capability-gated in the UI —
    // a router without a battery never shows the battery chart toggle.
    var transferChart: Bool = true
    var signalChart: Bool = true
    var batteryChart: Bool = true
    /// This Mac's own address on the device's network, with a copy button.
    var localIP: Bool = true

    init() {}

    /// Forgiving decode like the rest of the settings tree: a payload written
    /// before a toggle existed decodes to that toggle's default instead of
    /// throwing the user's whole configuration away.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = StatVisibility()
        basic = try c.decodeIfPresent(Bool.self, forKey: .basic) ?? d.basic
        radio = try c.decodeIfPresent(Bool.self, forKey: .radio) ?? d.radio
        transfer = try c.decodeIfPresent(Bool.self, forKey: .transfer) ?? d.transfer
        uptime = try c.decodeIfPresent(Bool.self, forKey: .uptime) ?? d.uptime
        session = try c.decodeIfPresent(Bool.self, forKey: .session) ?? d.session
        transferChart = try c.decodeIfPresent(Bool.self, forKey: .transferChart) ?? d.transferChart
        signalChart = try c.decodeIfPresent(Bool.self, forKey: .signalChart) ?? d.signalChart
        batteryChart = try c.decodeIfPresent(Bool.self, forKey: .batteryChart) ?? d.batteryChart
        localIP = try c.decodeIfPresent(Bool.self, forKey: .localIP) ?? d.localIP
    }
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
    /// The user's configured devices, first match wins. Never empty — v1's UI
    /// edits exactly `profiles[0]`.
    var profiles: [ModemProfile] = [.makeDefault(provider: .zte)]
    var refreshInterval: TimeInterval = Config.refreshInterval
    var language: AppLanguage = .system
    var showWhenDisconnected: Bool = false

    static let defaults = AppSettings()

    /// The stored profile with this id — the LIVE copy, not a snapshot.
    /// `ModemStore.activeProfile` is captured at refresh time; presentation
    /// reads the current settings through this so a toggle flipped in the
    /// settings window takes effect immediately, not on the next refresh.
    func profile(with id: UUID?) -> ModemProfile? {
        profiles.first { $0.id == id }
    }

    enum CodingKeys: String, CodingKey {
        case profiles, refreshInterval, language, showWhenDisconnected
        // Legacy flat keys (≤0.4.x). Read once during migration, never written.
        case networkMode, ssid, modemIP, stats, showBatteryPercent, batteryNotifications
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = AppSettings.defaults
        refreshInterval = try c.decodeIfPresent(TimeInterval.self, forKey: .refreshInterval) ?? d.refreshInterval
        language = try c.decodeIfPresent(AppLanguage.self, forKey: .language) ?? .system
        showWhenDisconnected = try c.decodeIfPresent(Bool.self, forKey: .showWhenDisconnected)
            ?? d.showWhenDisconnected

        if let stored = try c.decodeIfPresent([ModemProfile].self, forKey: .profiles),
           !stored.isEmpty {
            profiles = stored
        } else if c.contains(.profiles) {
            // Stored but empty: repair the never-empty invariant.
            profiles = d.profiles
        } else {
            // Legacy flat payload: fold every device-scoped key into one ZTE
            // profile so nothing the user configured is lost.
            var p = ModemProfile.makeDefault(provider: .zte)
            // The raw values of the retired flat network-mode enum.
            if try c.decodeIfPresent(String.self, forKey: .networkMode) == "byIPReachable" {
                p.matchMode = .ipProbe
            }
            p.ssid = try c.decodeIfPresent(String.self, forKey: .ssid) ?? p.ssid
            p.modemIP = try c.decodeIfPresent(String.self, forKey: .modemIP) ?? p.modemIP
            p.stats = try c.decodeIfPresent(StatVisibility.self, forKey: .stats) ?? p.stats
            p.showBatteryPercent = try c.decodeIfPresent(Bool.self, forKey: .showBatteryPercent)
                ?? p.showBatteryPercent
            p.batteryNotifications = try c.decodeIfPresent(BatteryNotificationSettings.self,
                                                           forKey: .batteryNotifications)
                ?? p.batteryNotifications
            profiles = [p]
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(profiles, forKey: .profiles)
        try c.encode(refreshInterval, forKey: .refreshInterval)
        try c.encode(language, forKey: .language)
        try c.encode(showWhenDisconnected, forKey: .showWhenDisconnected)
    }

    init() {}
}

// MARK: - Profile list operations

/// The only mutation paths for the profile list; views never index into
/// `profiles` directly. Stored order is matcher priority (first match wins).
extension AppSettings {
    /// Appends a fresh descriptor-prefilled profile; returns its id so the
    /// UI can select it.
    mutating func addProfile(provider: ProviderKind) -> UUID {
        let profile = ModemProfile.makeDefault(provider: provider)
        profiles.append(profile)
        return profile.id
    }

    /// Refuses to delete the last profile — the never-empty invariant that
    /// the decoder repairs is also enforced at the mutation edge.
    @discardableResult
    mutating func removeProfile(id: UUID) -> Bool {
        guard profiles.count > 1,
              let index = profiles.firstIndex(where: { $0.id == id }) else { return false }
        profiles.remove(at: index)
        return true
    }

    mutating func moveProfiles(fromOffsets: IndexSet, toOffset: Int) {
        profiles.move(fromOffsets: fromOffsets, toOffset: toOffset)
    }
}
