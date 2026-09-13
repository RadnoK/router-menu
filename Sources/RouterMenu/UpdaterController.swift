import Foundation
import Observation
import Sparkle

/// Wraps Sparkle for the settings UI.
///
/// Sparkle owns the preferences (automatic checks, interval) in UserDefaults —
/// we deliberately do not mirror them in AppSettings, to avoid two sources of
/// truth drifting apart.
@MainActor
@Observable
public final class UpdaterController {
    private let controller: SPUStandardUpdaterController
    private let channelDelegate: ChannelDelegate
    private let defaults: UserDefaults

    /// Bumped after a settings change so the view recomputes properties
    /// read directly from Sparkle.
    private var revision = 0

    /// Stored alongside Sparkle's own preferences rather than in AppSettings,
    /// for the same reason the rest of this file gives: one source of truth
    /// for update behaviour, read by the delegate Sparkle calls.
    private static let channelKey = "zte.updateChannel"

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let stored = defaults.string(forKey: Self.channelKey)
            .flatMap(UpdateChannel.init(rawValue:)) ?? .stable
        channelDelegate = ChannelDelegate(channel: stored)
        controller = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: channelDelegate,
            userDriverDelegate: nil
        )
    }

    /// Which releases this install is offered. Beta is additive — a beta user
    /// still receives stable releases.
    public var updateChannel: UpdateChannel {
        get {
            _ = revision
            return channelDelegate.channel
        }
        set {
            channelDelegate.channel = newValue
            defaults.set(newValue.rawValue, forKey: Self.channelKey)
            revision += 1
        }
    }

    private var updater: SPUUpdater { controller.updater }

    public var automaticallyChecksForUpdates: Bool {
        get {
            _ = revision
            return updater.automaticallyChecksForUpdates
        }
        set {
            updater.automaticallyChecksForUpdates = newValue
            revision += 1
        }
    }

    public var automaticallyDownloadsUpdates: Bool {
        get {
            _ = revision
            return updater.automaticallyDownloadsUpdates
        }
        set {
            updater.automaticallyDownloadsUpdates = newValue
            revision += 1
        }
    }

    /// Check interval in seconds; Sparkle enforces a minimum of 1 hour.
    public var updateCheckInterval: TimeInterval {
        get {
            _ = revision
            return updater.updateCheckInterval
        }
        set {
            updater.updateCheckInterval = newValue
            revision += 1
        }
    }

    public var lastUpdateCheckDate: Date? {
        _ = revision
        return updater.lastUpdateCheckDate
    }

    public var canCheckForUpdates: Bool {
        _ = revision
        return updater.canCheckForUpdates
    }

    /// Manual check — shows Sparkle's UI even when there is no new version.
    public func checkForUpdates() {
        updater.checkForUpdates()
        revision += 1
    }
}

/// Tells Sparkle which appcast channels this install accepts.
///
/// Sparkle asks its delegate on every check, so flipping the channel takes
/// effect on the next check without restarting the updater. NSObject-based
/// because `SPUUpdaterDelegate` is an Objective-C protocol.
private final class ChannelDelegate: NSObject, SPUUpdaterDelegate {
    var channel: UpdateChannel

    init(channel: UpdateChannel) {
        self.channel = channel
    }

    func allowedChannels(for updater: SPUUpdater) -> Set<String> {
        channel.allowedChannels
    }
}
