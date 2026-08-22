import SwiftUI

public struct ZteMenuApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @Environment(\.openWindow) private var openWindow

    public init() {}

    public var body: some Scene {
        let store = appDelegate.store
        let settings = appDelegate.settings
        let p = MenuBarPresentation.make(for: store.state)

        MenuBarExtra(isInserted: .constant(p.isVisible)) {
            PopoverView(store: store, settings: settings) {
                openWindow(id: "settings")
                NSApplication.shared.activate(ignoringOtherApps: true)
            }
        } label: {
            Image(systemName: p.symbolName, variableValue: p.variableValue)
        }
        .menuBarExtraStyle(.window)

        Window("Ustawienia ZTE Menu", id: "settings") {
            SettingsView(settings: settings, updater: appDelegate.updater)
        }
        .windowResizability(.contentSize)
    }
}
