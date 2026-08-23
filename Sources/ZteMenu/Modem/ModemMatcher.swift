import Foundation
import CoreWLAN

public protocol SSIDReading: Sendable {
    func currentSSID() -> String?
}

public struct CoreWLANReader: SSIDReading {
    public init() {}

    public func currentSSID() -> String? {
        CWWiFiClient.shared().interface()?.ssid()
    }
}

/// The outcome of scanning the profile list for a nearby device.
enum MatchResult: Equatable {
    case matched(ModemProfile)
    /// Nothing matched. `ssidSkipped` reports whether any `.ssid` profile
    /// could not be evaluated because location permission is denied — the
    /// difference between "hide the icon" and "explain the permission".
    case none(ssidSkipped: Bool)
}

/// Decides which configured device, if any, we are next to right now.
struct ModemMatcher {
    let reader: SSIDReading

    init(reader: SSIDReading = CoreWLANReader()) {
        self.reader = reader
    }

    /// First match wins, in stored order.
    /// - Parameter probe: asks a profile's driver whether its device answers,
    ///   injected so the matcher stays free of HTTP. `@MainActor` because the
    ///   store's driver factory is main-actor-bound.
    @MainActor
    func match(in profiles: [ModemProfile],
               locationAuthorized: Bool,
               probe: (ModemProfile) async -> Bool) async -> MatchResult {
        var ssidSkipped = false
        // One CoreWLAN read per scan, not per profile.
        let currentSSID = locationAuthorized ? reader.currentSSID() : nil
        for profile in profiles {
            switch profile.matchMode {
            case .ssid:
                guard locationAuthorized else {
                    ssidSkipped = true
                    continue
                }
                if currentSSID == profile.ssid { return .matched(profile) }
            case .ipProbe:
                if await probe(profile) { return .matched(profile) }
            }
        }
        return .none(ssidSkipped: ssidSkipped)
    }
}
