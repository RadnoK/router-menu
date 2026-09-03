import Foundation

/// Which device family a profile talks to. Raw values are persisted.
enum ProviderKind: String, Codable, CaseIterable, Sendable {
    case zte
    case asus
    /// A tethered phone. Named for the feature, not the vendor: Android
    /// tethering presents the Mac with the same interface to read.
    case hotspot
}

extension ProviderKind {
    /// Whether the "device" is a phone sharing its connection rather than a
    /// modem or router. The Mac sees the LINK to it, never its radio or
    /// battery, which the menu bar symbol has to reflect.
    var isTether: Bool { self == .hotspot }
}

/// What the panel password unlocks on a device, so credential UI can be
/// described without knowing the brand.
enum PasswordRole: Sendable, Equatable {
    case none
    /// Status is public; the transfer counters need a login (ZTE U50).
    case unlocksTraffic
    case requiredForAll
}

/// Facts about a device family — facts, not preferences. A router without a
/// battery has no battery UI to configure.
struct ModemCapabilities: Sendable, Equatable {
    let hasBattery: Bool
    let passwordRole: PasswordRole
    /// Whether the device's login has a username component (Asus) or is
    /// password-only (ZTE). Drives the credentials UI.
    let needsUsername: Bool
    /// Cellular modems report bars/RSRP; a wired router has no radio to
    /// grade. Drives the menu bar symbol and the popover's signal row.
    let hasRadioSignal: Bool
    /// Whether the device reports per-session data counters (ZTE's
    /// realtime_*_bytes). Drives the session row and its settings toggle.
    let hasSessionCounters: Bool
}

/// How a provider describes itself: identity for the UI, defaults for fresh
/// profiles, capability gates, and the factory producing its driver.
struct ProviderDescriptor: Sendable {
    let displayName: String
    let defaultBaseURL: URL
    let defaultSSID: String
    let supportedMatchModes: [MatchMode]
    let defaultMatchMode: MatchMode
    let capabilities: ModemCapabilities
    let makeDriver: @Sendable (_ profile: ModemProfile, _ password: String?, _ http: any HTTPFetching) -> any ModemDriving
}

enum ProviderCatalog {
    /// An exhaustive switch on purpose: adding a `ProviderKind` case without
    /// wiring its descriptor is a compile error here, not a runtime miss.
    static func descriptor(for kind: ProviderKind) -> ProviderDescriptor {
        switch kind {
        case .zte: return ZTEProvider.descriptor
        case .asus: return AsusProvider.descriptor
        case .hotspot: return HotspotProvider.descriptor
        }
    }
}
