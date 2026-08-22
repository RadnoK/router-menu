import SwiftUI

/// Tabbed settings window, the standard shape for a macOS app with more than a
/// couple of preference groups.
///
/// The tab strip is `SettingsTabBar` rather than `TabView`'s built-in one,
/// because a `Window` scene renders `TabView` in its content style and drops the
/// tab icons. Each tab owns its own `Form`; this type composes them, tracks the
/// selection, and keeps the language in sync.
public struct SettingsView: View {
    @Bindable private var settings: SettingsStore
    @Bindable private var updater: UpdaterController
    private let l10n: L10n

    @State private var selection: SettingsTab = .general

    public init(settings: SettingsStore, updater: UpdaterController, l10n: L10n) {
        self.settings = settings
        self.updater = updater
        self.l10n = l10n
    }

    public var body: some View {
        VStack(spacing: 0) {
            SettingsTabBar(selection: $selection, l10n: l10n)
            Divider()
            content
        }
        .frame(width: 460)
        .onChange(of: settings.settings.language) { _, new in
            l10n.setLanguage(new)
        }
    }

    @ViewBuilder
    private var content: some View {
        switch selection {
        case .general:
            GeneralSettingsTab(settings: settings, l10n: l10n)
        case .panel:
            PanelSettingsTab(settings: settings, l10n: l10n)
        case .account:
            AccountSettingsTab(l10n: l10n)
        case .updates:
            UpdatesSettingsTab(updater: updater, l10n: l10n)
        }
    }
}
