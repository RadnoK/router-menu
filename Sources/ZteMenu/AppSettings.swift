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

struct AppSettings: Codable, Equatable {
    var networkMode: NetworkMode = .bySSID
    var ssid: String = Config.targetSSID
    var modemIP: String = "192.168.0.1"
    var refreshInterval: TimeInterval = Config.refreshInterval
    var stats: StatVisibility = StatVisibility()
    var language: AppLanguage = .system

    static let defaults = AppSettings()

    /// Settings saved by 0.2.1 and earlier carry no `language` key. Decoding
    /// each field individually keeps those payloads loadable instead of
    /// throwing and silently resetting every preference.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = AppSettings.defaults
        networkMode = try c.decodeIfPresent(NetworkMode.self, forKey: .networkMode) ?? d.networkMode
        ssid = try c.decodeIfPresent(String.self, forKey: .ssid) ?? d.ssid
        modemIP = try c.decodeIfPresent(String.self, forKey: .modemIP) ?? d.modemIP
        refreshInterval = try c.decodeIfPresent(TimeInterval.self, forKey: .refreshInterval) ?? d.refreshInterval
        stats = try c.decodeIfPresent(StatVisibility.self, forKey: .stats) ?? d.stats
        language = try c.decodeIfPresent(AppLanguage.self, forKey: .language) ?? .system
    }

    init() {}
}
