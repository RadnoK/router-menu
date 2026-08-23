import SwiftUI

/// What the menu bar shows: when the icon is present at all, and which stat
/// groups its popover lists.
struct PanelSettingsTab: View {
    @Bindable var settings: SettingsStore
    let l10n: L10n

    var body: some View {
        Form {
            Section {
                Toggle(l10n(.settingsShowWhenDisconnected),
                       isOn: $settings.settings.showWhenDisconnected)
                    .help(l10n(.settingsShowWhenDisconnectedHelp))
            }

            Section {
                Toggle(l10n(.settingsStatsBasic), isOn: $settings.profile.stats.basic)
                Toggle(l10n(.settingsStatsRadio), isOn: $settings.profile.stats.radio)
                Toggle(l10n(.settingsStatsTransfer), isOn: $settings.profile.stats.transfer)
                Toggle(l10n(.settingsStatsUptime), isOn: $settings.profile.stats.uptime)
            }
        }
        .formStyle(.grouped)
    }
}
