import Foundation

/// How a profile recognises that its device is nearby.
/// Raw values are persisted inside profiles — do not rename cases.
enum MatchMode: String, Codable, CaseIterable, Sendable {
    /// Compare the current Wi-Fi network name (needs location permission).
    case ssid
    /// Ask the provider's driver whether the device answers at the address.
    case ipProbe
}
