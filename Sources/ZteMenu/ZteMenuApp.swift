import SwiftUI

public struct ZteMenuApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @Environment(\.openWindow) private var openWindow

    public init() {}

    public var body: some Scene {
        let store = appDelegate.store
        let settings = appDelegate.settings
        let l10n = appDelegate.l10n
        let p = MenuBarPresentation.make(for: store.state)

        MenuBarExtra(isInserted: .constant(p.isVisible)) {
            PopoverView(store: store, settings: settings, l10n: l10n) {
                openWindow(id: "settings")
                NSApplication.shared.activate(ignoringOtherApps: true)
            }
        } label: {
            Image(systemName: p.symbolName, variableValue: p.variableValue)
        }
        .menuBarExtraStyle(.window)

        Window(l10n(.settingsWindowTitle), id: "settings") {
            SettingsView(settings: settings, updater: appDelegate.updater, l10n: l10n)
        }
        .windowResizability(.contentSize)
    }
}
