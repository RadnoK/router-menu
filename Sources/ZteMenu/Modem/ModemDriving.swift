import Foundation

/// A modem/router protocol driver. One implementation per provider; the rest
/// of the app talks to a device only through this seam.
protocol ModemDriving: Sendable {
    /// Read the device's current state.
    func fetch() async throws -> ModemData
    /// Whether THIS provider's device answers at the configured address.
    /// Used by IP-probe matching. Plain reachability is an acceptable v1;
    /// a provider can later strengthen it to a protocol-level fingerprint.
    func probe() async -> Bool
}
