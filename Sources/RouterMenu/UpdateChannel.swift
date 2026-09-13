import Foundation

/// Which releases the updater is willing to offer.
///
/// Sparkle models this with `sparkle:channel` on an appcast item: an item with
/// no channel is the default (stable) one that everybody receives, and an item
/// tagged with a channel is only offered to updaters that explicitly allow it.
/// So "beta" is additive — a beta user still gets stable releases, and is
/// simply also shown the pre-releases.
public enum UpdateChannel: String, Codable, CaseIterable, Sendable {
    case stable
    case beta

    /// The channel name written into the appcast. Stable items carry no
    /// channel at all, which is what makes them visible to every user.
    public static let betaChannelName = "beta"

    /// What `SPUUpdaterDelegate.allowedChannels` should return.
    public var allowedChannels: Set<String> {
        switch self {
        case .stable: return []
        case .beta: return [Self.betaChannelName]
        }
    }

    /// Whether a version string denotes a pre-release, by the convention the
    /// release script and CI use: a hyphen suffix (0.7.0-beta.1). Kept here so
    /// the app, the release script and the appcast all agree on one rule.
    public static func isPrerelease(version: String) -> Bool {
        version.contains("-")
    }
}
