import SwiftUI

/// Startup, menu-bar visibility and interface language — the settings a user
/// is most likely to open the window for.
struct GeneralSettingsTab: View {
    @Bindable var settings: SettingsStore
    let l10n: L10n
    /// Owns the login-item registration; the toggle reads the system's state
    /// through it rather than keeping a preference of its own.
    @Bindable var loginItem: LoginItemController

    var body: some View {
        Form {
            Section {
                Toggle(l10n(.settingsLaunchAtLogin), isOn: Binding(
                    get: { loginItem.isEnabled },
                    // Not a stored preference: the setter hands the change to
                    // the system, then the toggle shows whatever the system
                    // ended up with.
                    set: { loginItem.setEnabled($0) }
                ))
                .help(l10n(.settingsLaunchAtLoginHelp))
                if let error = loginItem.lastError {
                    Text(l10n(.settingsLaunchAtLoginError, error))
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
            }

            Section {
                Toggle(l10n(.settingsShowWhenDisconnected),
                       isOn: $settings.settings.showWhenDisconnected)
                    .help(l10n(.settingsShowWhenDisconnectedHelp))
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
        .task {
            // The user may have removed the app from Login Items while this
            // window was closed.
            loginItem.refresh()
        }
    }
}
