import Foundation

/// How a profile recognises that its device is nearby.
/// Raw values are persisted inside profiles — do not rename cases.
enum MatchMode: String, Codable, CaseIterable, Sendable {
    /// Compare the current Wi-Fi network name (needs location permission).
    case ssid
    /// Ask the provider's driver whether the device answers at the address.
    case ipProbe
}

/// One configured device: which provider drives it, how to recognise being
/// near it, where it lives — and how the user wants THIS device presented.
/// Battery and stat preferences are per-profile ("contextual"): a mains-powered
/// router simply has none of them.
struct ModemProfile: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    var provider: ProviderKind
    var matchMode: MatchMode
    /// Used by `.ssid` matching.
    var ssid: String
    /// The driver's address, and the `.ipProbe` target.
    var modemIP: String
    var showBatteryPercent: Bool
    var batteryNotifications: BatteryNotificationSettings
    var stats: StatVisibility

    init(id: UUID = UUID(),
         provider: ProviderKind,
         matchMode: MatchMode,
         ssid: String,
         modemIP: String,
         showBatteryPercent: Bool = false,
         batteryNotifications: BatteryNotificationSettings = BatteryNotificationSettings(),
         stats: StatVisibility = StatVisibility()) {
        self.id = id
        self.provider = provider
        self.matchMode = matchMode
        self.ssid = ssid
        self.modemIP = modemIP
        self.showBatteryPercent = showBatteryPercent
        self.batteryNotifications = batteryNotifications
        self.stats = stats
    }

    /// A fresh profile for a provider, prefilled from its descriptor.
    static func makeDefault(provider: ProviderKind) -> ModemProfile {
        let d = ProviderCatalog.descriptor(for: provider)
        return ModemProfile(provider: provider,
                            matchMode: d.defaultMatchMode,
                            ssid: d.defaultSSID,
                            modemIP: d.defaultBaseURL.host ?? "192.168.0.1")
    }

    var baseURL: URL {
        guard let url = URL(string: "http://\(modemIP)"), url.host != nil else {
            return ProviderCatalog.descriptor(for: provider).defaultBaseURL
        }
        return url
    }

    /// Field-by-field forgiving decode, same style as `AppSettings`: an
    /// unknown or missing key falls to its default instead of throwing away
    /// the user's whole configuration.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        provider = try c.decodeIfPresent(ProviderKind.self, forKey: .provider) ?? .zte
        matchMode = try c.decodeIfPresent(MatchMode.self, forKey: .matchMode) ?? .ssid
        ssid = try c.decodeIfPresent(String.self, forKey: .ssid) ?? ""
        modemIP = try c.decodeIfPresent(String.self, forKey: .modemIP) ?? "192.168.0.1"
        showBatteryPercent = try c.decodeIfPresent(Bool.self, forKey: .showBatteryPercent) ?? false
        batteryNotifications = try c.decodeIfPresent(BatteryNotificationSettings.self,
                                                     forKey: .batteryNotifications)
            ?? BatteryNotificationSettings()
        stats = try c.decodeIfPresent(StatVisibility.self, forKey: .stats) ?? StatVisibility()
    }
}
