import SwiftUI

public struct RouterMenuApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    public init() {}

    public var body: some Scene {
        let store = appDelegate.store
        let settings = appDelegate.settings
        let l10n = appDelegate.l10n
        let activeProfile = settings.settings.profile(with: store.activeProfile?.id)
            ?? store.activeProfile
        let showsRadioSignal = activeProfile
            .map { ProviderCatalog.descriptor(for: $0.provider).capabilities.hasRadioSignal }
            ?? true
        let p = MenuBarPresentation.make(for: store.state,
                                         showBatteryPercent: activeProfile?.showBatteryPercent ?? false,
                                         showWhenDisconnected: settings.settings.showWhenDisconnected,
                                         showsRadioSignal: showsRadioSignal,
                                         isTether: activeProfile?.provider.isTether ?? false)

        MenuBarExtra(isInserted: .constant(p.isVisible)) {
            PopoverView(store: store, settings: settings, l10n: l10n) {
                SettingsWindowOpener.open()
            }
        } label: {
            // One label view, not two branches: `MenuBarExtra` re-creates the
            // label whenever the presentation changes, and a stable view tree
            // keeps the icon from flickering as the percentage updates.
            HStack(spacing: 3) {
                Image(systemName: p.symbolName, variableValue: p.variableValue)
                if let text = p.batteryText {
                    Text(text)
                }
            }
        }
        .menuBarExtraStyle(.window)

        // A Settings scene, not a Window: only this one renders TabView with
        // macOS's native preference toolbar, and it supplies the "Settings…"
        // menu item and Command-, shortcut for free. Opening it from the
        // popover goes through SettingsWindowOpener.
        Settings {
            SettingsView(settings: settings,
                         updater: appDelegate.updater,
                         store: appDelegate.store,
                         l10n: l10n,
                         loginItem: appDelegate.loginItem,
                         onNotificationsEnabled: appDelegate.requestNotificationAuthorization)
        }
    }
}
