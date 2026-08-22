import SwiftUI

/// Tabbed settings window, the standard shape for a macOS app with more than a
/// couple of preference groups.
///
/// Each tab owns its own `Form`; this type only composes them and keeps the
/// language in sync. The window has no fixed height — it resizes to whichever
/// tab is showing, which is the native behaviour.
public struct SettingsView: View {
    @Bindable private var settings: SettingsStore
    @Bindable private var updater: UpdaterController
    private let l10n: L10n

    public init(settings: SettingsStore, updater: UpdaterController, l10n: L10n) {
        self.settings = settings
        self.updater = updater
        self.l10n = l10n
    }

    public var body: some View {
        TabView {
            GeneralSettingsTab(settings: settings, l10n: l10n)
                .tabItem { Label(l10n(.settingsTabGeneral), systemImage: "gearshape") }

            PanelSettingsTab(settings: settings, l10n: l10n)
                .tabItem { Label(l10n(.settingsTabPanel), systemImage: "menubar.rectangle") }

            AccountSettingsTab(l10n: l10n)
                .tabItem { Label(l10n(.settingsTabAccount), systemImage: "key") }

            UpdatesSettingsTab(updater: updater, l10n: l10n)
                .tabItem { Label(l10n(.settingsTabUpdates), systemImage: "arrow.triangle.2.circlepath") }
        }
        .frame(width: 460)
        .onChange(of: settings.settings.language) { _, new in
            l10n.setLanguage(new)
        }
    }
}
