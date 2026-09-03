import AppKit
import SwiftUI

/// Drives the app's lifecycle: holds the shared `ModemStore`, requests
/// location permission, and runs the refresh loop — all independent of
/// whether the menu bar icon is currently visible.
///
/// The bootstrap MUST live here, not in the menu content view: `MenuBarExtra`
/// only renders its content (and its `.task`) once the menu is opened, and
/// the menu can't be opened while the icon is hidden (the startup state is
/// `.hidden`). If the loop lived in the view, it would never start.
@MainActor
public final class AppDelegate: NSObject, NSApplicationDelegate {
    /// Shared, observable source of truth — read by the icon label as well
    /// as the popover view and the settings window.
    public let settings = SettingsStore()
    public let updater = UpdaterController()
    public let history = HistoryStore()
    public let loginItem = LoginItemController()
    public lazy var l10n = L10n(language: settings.settings.language)
    public lazy var store = ModemStore(settings: settings, history: history)
    private lazy var batteryNotifier = BatteryNotifier(settings: settings, l10n: l10n)
    private let permission = LocationPermission()
    private var refreshTask: Task<Void, Never>?
    /// Retains the right-click monitor on the menu bar icon; releasing it
    /// would remove the event monitor.
    private var statusItemObserver: RightClickMonitor?

    public func applicationDidFinishLaunching(_ notification: Notification) {
        l10n.setLanguage(settings.settings.language)
        // One-time: the pre-device-manager app kept a single password slot.
        // profiles[0] is the profile the settings migration built from those
        // same legacy settings, so the password belongs to it.
        Keychain.migrateLegacyPassword(to: settings.settings.profiles[0].id)
        store.setBatteryNotifier(batteryNotifier)
        // The default profile ships with battery thresholds armed, so on a
        // fresh install this asks for notification permission on first launch;
        // afterwards it is a no-op (macOS only ever prompts once).
        batteryNotifier.requestAuthorizationIfNeeded()
        // A location-permission change (e.g. the user taps "Allow") must refresh
        // state IMMEDIATELY — otherwise the icon would only appear on the next
        // loop tick, up to 60 s later. Verified live: permission settles ~3 s
        // after launch, after which the state flips to connected.
        permission.onChange = { [weak self] auth in
            self?.store.setLocationAuth(auth)
            self?.triggerRefresh()
        }
        store.setLocationAuth(permission.status)
        permission.requestIfNeeded()
        startRefreshLoop()
        attachStatusItemMenu()
    }

    /// Gives the menu bar icon a right-click menu.
    ///
    /// `MenuBarExtra` keeps its `NSStatusItem` private and creates it lazily,
    /// so there is nothing to attach to at launch. The item shows up as a
    /// status-bar window, which is what this looks for — retrying briefly
    /// rather than assuming a fixed delay, since the icon also appears (and
    /// disappears) later as the modem comes and goes.
    private func attachStatusItemMenu() {
        Task { @MainActor [weak self] in
            for _ in 0..<20 {
                if let self, self.installMenuOnStatusItem() { return }
                try? await Task.sleep(for: .milliseconds(250))
            }
        }
    }

    /// Walks the app's windows for the one hosting the status item's button.
    /// Returns whether the menu found a home.
    @discardableResult
    private func installMenuOnStatusItem() -> Bool {
        for window in NSApp.windows {
            guard let button = Self.statusButton(in: window.contentView) else { continue }
            // NOT `button.menu = …`: AppKit pops an assigned menu on EVERY
            // click, which swallows the primary one and leaves the popover
            // unopenable (verified — the popover stopped appearing). Instead
            // the right click is intercepted here and the menu popped by hand,
            // leaving MenuBarExtra's own left-click handling untouched.
            let monitor = RightClickMonitor(button: button) { [weak self] in
                guard let self else { return }
                let menu = StatusItemMenu.make(l10n: self.l10n)
                menu.popUp(positioning: nil,
                           at: NSPoint(x: 0, y: button.bounds.height + 4),
                           in: button)
            }
            statusItemObserver = monitor
            return true
        }
        return false
    }

    private static func statusButton(in view: NSView?) -> NSStatusBarButton? {
        guard let view else { return nil }
        if let button = view as? NSStatusBarButton { return button }
        for subview in view.subviews {
            if let button = statusButton(in: subview) { return button }
        }
        return nil
    }

    /// Called by the settings window the moment the user arms the first alert.
    public func requestNotificationAuthorization() {
        batteryNotifier.requestAuthorizationIfNeeded()
    }

    private func startRefreshLoop() {
        refreshTask?.cancel()
        refreshTask = Task { [store] in
            await store.refresh()
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(Config.refreshInterval))
                await store.refresh()
            }
        }
    }

    private func triggerRefresh() {
        Task { [store] in await store.refresh() }
    }

    public func applicationWillTerminate(_ notification: Notification) {
        refreshTask?.cancel()
    }

    /// The menu bar app must NOT quit when the settings window closes.
    /// By default, SwiftUI's `Window` scene returns `true` here and ends the
    /// process once there are no open windows — which makes the icon "vanish"
    /// shortly after. The menu bar lives independently of windows, so we
    /// return `false`.
    public func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    /// Launching the app again while it runs (Finder, Dock, `open -a`) lands
    /// here. With "hide the icon when disconnected" on and the Mac away from
    /// the configured network there is no icon to click, so this is the only
    /// way back into the app — route it to the settings window.
    public func applicationShouldHandleReopen(_ sender: NSApplication,
                                              hasVisibleWindows: Bool) -> Bool {
        SettingsWindowOpener.open()
        return false
    }
}
