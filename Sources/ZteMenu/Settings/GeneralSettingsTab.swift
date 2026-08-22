import SwiftUI

/// Network detection and interface language — the settings a user is most
/// likely to open the window for.
struct GeneralSettingsTab: View {
    @Bindable var settings: SettingsStore
    let l10n: L10n

    /// Read once at appear rather than at init: the current network can change
    /// while the window is open, and reading it in `body` would hit CoreWLAN on
    /// every redraw.
    @State private var currentSSID: String?

    var body: some View {
        Form {
            Section {
                Picker(l10n(.settingsDetectionMode), selection: $settings.settings.networkMode) {
                    Text(l10n(.settingsDetectionBySSID)).tag(NetworkMode.bySSID)
                    Text(l10n(.settingsDetectionByIP)).tag(NetworkMode.byIPReachable)
                }
                LabeledContent(l10n(.settingsCurrentNetwork),
                               value: currentSSID ?? l10n(.placeholderDash))

                if settings.settings.networkMode == .bySSID {
                    TextField(l10n(.settingsSSIDField), text: $settings.settings.ssid)
                        .help(l10n(.settingsSSIDHelp))
                } else {
                    TextField(l10n(.settingsModemIPField), text: $settings.settings.modemIP)
                        .help(l10n(.settingsModemIPHelp))
                }
            }

            Section {
                Picker(l10n(.settingsLanguage), selection: $settings.settings.language) {
                    Text(l10n(.settingsLanguageSystem)).tag(AppLanguage.system)
                    Text(l10n(.settingsLanguagePolish)).tag(AppLanguage.pl)
                    Text(l10n(.settingsLanguageEnglish)).tag(AppLanguage.en)
                }
            }
        }
        .formStyle(.grouped)
        .task { currentSSID = CoreWLANReader().currentSSID() }
    }
}
