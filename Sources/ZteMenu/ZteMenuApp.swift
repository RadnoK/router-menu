import SwiftUI

public struct ZteMenuApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    public init() {}

    public var body: some Scene {
        let store = appDelegate.store
        let settings = appDelegate.settings
        let l10n = appDelegate.l10n
        let p = MenuBarPresentation.make(for: store.state)

        MenuBarExtra(isInserted: .constant(p.isVisible)) {
            PopoverView(store: store, settings: settings, l10n: l10n) {
                Self.openSettings()
            }
        } label: {
            Image(systemName: p.symbolName, variableValue: p.variableValue)
        }
        .menuBarExtraStyle(.window)

        // The Settings scene gives us the standard "Settings…" menu item, the
        // Command-, shortcut and the system-supplied window title for free.
        Settings {
            SettingsView(settings: settings, updater: appDelegate.updater, l10n: l10n)
        }
    }

    /// Opens the settings window from the menu bar popover.
    ///
    /// `LSUIElement` apps are not activated by clicking the menu bar item, so
    /// the window would open behind whatever the user was working in. Activating
    /// first puts it in front.
    @MainActor
    static func openSettings() {
        NSApplication.shared.activate(ignoringOtherApps: true)
        // The selector moved in Ventura; try the current one, then the legacy
        // name, so this keeps working across the supported macOS range.
        let modern = Selector(("showSettingsWindow:"))
        let legacy = Selector(("showPreferencesWindow:"))
        if NSApplication.shared.responds(to: modern) {
            NSApplication.shared.perform(modern, with: nil)
        } else {
            NSApplication.shared.perform(legacy, with: nil)
        }
    }
}
