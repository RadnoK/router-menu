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
                SettingsWindowOpener.open()
            }
        } label: {
            Image(systemName: p.symbolName, variableValue: p.variableValue)
        }
        .menuBarExtraStyle(.window)

        // A Settings scene, not a Window: only this one renders TabView with
        // macOS's native preference toolbar, and it supplies the "Settings…"
        // menu item and Command-, shortcut for free. Opening it from the
        // popover goes through SettingsWindowOpener.
        Settings {
            SettingsView(settings: settings, updater: appDelegate.updater, l10n: l10n)
        }
    }
}
