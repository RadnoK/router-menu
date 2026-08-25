import AppKit

/// Opens the app's `Settings` scene from code.
///
/// SwiftUI wires the Settings scene to the "Settings…" item in the app menu and
/// exposes no API to open it. `NSApplication` does not implement
/// `showSettingsWindow:` or `showPreferencesWindow:` either — verified in
/// `SettingsWindowTests` — so the only reliable route is to trigger that menu
/// item the way a click would.
enum SettingsWindowOpener {
    /// Menu items SwiftUI may use for the Settings scene, across macOS versions.
    /// Matched by action name so a localized title cannot break the lookup.
    static let actionNames = ["showSettingsWindow:", "showPreferencesWindow:", "menuAction:"]

    @MainActor
    static func open() {
        // An LSUIElement app is not activated by a menu bar click, so without
        // this the window opens behind the frontmost app.
        NSApplication.shared.activate(ignoringOtherApps: true)

        guard let submenu = NSApplication.shared.mainMenu?.item(at: 0)?.submenu,
              let index = settingsItemIndex(in: submenu) else { return }
        submenu.performActionForItem(at: index)
    }

    /// The Settings item sits in the app menu, between About and Services.
    /// Prefer an exact action match; fall back to the standard Command-,
    /// shortcut, which SwiftUI assigns to that item.
    @MainActor
    static func settingsItemIndex(in submenu: NSMenu) -> Int? {
        for i in 0..<submenu.numberOfItems {
            guard let item = submenu.item(at: i) else { continue }
            if let action = item.action, actionNames.contains(NSStringFromSelector(action)),
               item.keyEquivalent == "," {
                return i
            }
        }
        for i in 0..<submenu.numberOfItems {
            guard let item = submenu.item(at: i) else { continue }
            if item.keyEquivalent == "," && item.keyEquivalentModifierMask == .command {
                return i
            }
        }
        return nil
    }
}
