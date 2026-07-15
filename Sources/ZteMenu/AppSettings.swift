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

    static let defaults = AppSettings()
}
