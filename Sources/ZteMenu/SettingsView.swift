import SwiftUI

/// Tabbed settings window.
///
/// Inside a `Settings` scene, `TabView` renders macOS's native preference
/// toolbar — an icon above each label, with the window title tracking the
/// selected tab. The same `TabView` in a plain `Window` scene falls back to a
/// content-style strip that drops the icons, which is why the scene type
/// matters here. Each tab owns its own `Form`; this type only composes them.
public struct SettingsView: View {
    @Bindable private var settings: SettingsStore
    @Bindable private var updater: UpdaterController
    private let l10n: L10n
    @Bindable private var loginItem: LoginItemController
    private let onNotificationsEnabled: () -> Void

    public init(settings: SettingsStore,
                updater: UpdaterController,
                l10n: L10n,
                loginItem: LoginItemController,
                onNotificationsEnabled: @escaping () -> Void = {}) {
        self.settings = settings
        self.updater = updater
        self.l10n = l10n
        self.loginItem = loginItem
        self.onNotificationsEnabled = onNotificationsEnabled
    }

    public var body: some View {
        TabView {
            ForEach(SettingsTab.allCases) { tab in
                content(for: tab)
                    .tabItem { Label(l10n(tab.titleKey), systemImage: tab.symbolName) }
                    .tag(tab)
            }
        }
        .frame(width: 460)
        .onChange(of: settings.settings.language) { _, new in
            l10n.setLanguage(new)
        }
    }

    @ViewBuilder
    private func content(for tab: SettingsTab) -> some View {
        switch tab {
        case .general:
            GeneralSettingsTab(settings: settings, l10n: l10n, loginItem: loginItem)
        case .panel:
            PanelSettingsTab(settings: settings, l10n: l10n)
        case .battery:
            BatterySettingsTab(settings: settings,
                               l10n: l10n,
                               onNotificationsEnabled: onNotificationsEnabled)
        case .account:
            AccountSettingsTab(l10n: l10n)
        case .updates:
            UpdatesSettingsTab(updater: updater, l10n: l10n)
        }
    }
}
