import Foundation

/// Which device family a profile talks to. Raw values are persisted.
enum ProviderKind: String, Codable, CaseIterable, Sendable {
    case zte
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
    let makeDriver: @Sendable (_ baseURL: URL, _ password: String?, _ http: any HTTPFetching) -> any ModemDriving
}

enum ProviderCatalog {
    /// An exhaustive switch on purpose: adding a `ProviderKind` case without
    /// wiring its descriptor is a compile error here, not a runtime miss.
    static func descriptor(for kind: ProviderKind) -> ProviderDescriptor {
        switch kind {
        case .zte: return ZTEProvider.descriptor
        }
    }
}
