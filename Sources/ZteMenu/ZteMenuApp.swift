import SwiftUI

public struct ZteMenuApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @Environment(\.openWindow) private var openWindow

    /// Shared by the scene that declares the window and the popover that opens
    /// it. Keeping it in one place is what the test pins.
    static let settingsWindowID = "settings"

    public init() {}

    public var body: some Scene {
        let store = appDelegate.store
        let settings = appDelegate.settings
        let l10n = appDelegate.l10n
        let p = MenuBarPresentation.make(for: store.state)

        MenuBarExtra(isInserted: .constant(p.isVisible)) {
            PopoverView(store: store, settings: settings, l10n: l10n) {
                // `LSUIElement` apps are not activated by a menu bar click, so
                // the window would otherwise open behind the frontmost app.
                NSApplication.shared.activate(ignoringOtherApps: true)
                openWindow(id: Self.settingsWindowID)
            }
        } label: {
            Image(systemName: p.symbolName, variableValue: p.variableValue)
        }
        .menuBarExtraStyle(.window)

        // A `Window` scene, not `Settings`: opening a `Settings` scene from code
        // requires `showSettingsWindow:`, which `NSApplication` does not
        // implement — SwiftUI binds that menu item internally, so the popover
        // button had no way to reach it. `SettingsWindowTests` pins this.
        Window(l10n(.settingsWindowTitle), id: Self.settingsWindowID) {
            SettingsView(settings: settings, updater: appDelegate.updater, l10n: l10n)
        }
        .windowResizability(.contentSize)
        .defaultPosition(.center)
        .keyboardShortcut(",", modifiers: .command)
    }
}
