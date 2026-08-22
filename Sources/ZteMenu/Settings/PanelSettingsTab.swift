import SwiftUI

/// Which stat groups the menu bar popover shows.
struct PanelSettingsTab: View {
    @Bindable var settings: SettingsStore
    let l10n: L10n

    var body: some View {
        Form {
            Section {
                Toggle(l10n(.settingsStatsBasic), isOn: $settings.settings.stats.basic)
                Toggle(l10n(.settingsStatsRadio), isOn: $settings.settings.stats.radio)
                Toggle(l10n(.settingsStatsTransfer), isOn: $settings.settings.stats.transfer)
                Toggle(l10n(.settingsStatsUptime), isOn: $settings.settings.stats.uptime)
            }
        }
        .formStyle(.grouped)
    }
}
