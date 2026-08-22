import SwiftUI

public struct SettingsView: View {
    @Bindable private var settings: SettingsStore
    @Bindable private var updater: UpdaterController
    private let l10n: L10n
    @State private var password: String = Keychain.password() ?? ""
    @State private var currentSSID: String

    public init(settings: SettingsStore, updater: UpdaterController, l10n: L10n) {
        self.settings = settings
        self.updater = updater
        self.l10n = l10n
        // The placeholder is resolved once at init and frozen in @State, so it
        // does NOT re-localize when the user switches language. That is only
        // safe because `placeholder_dash` is an em dash — identical in every
        // language. If it ever becomes real translated text, this must move to
        // a computed value that reads `l10n` at render time.
        _currentSSID = State(initialValue: CoreWLANReader().currentSSID()
                             ?? l10n(.placeholderDash))
    }

    public var body: some View {
        Form {
            Section(l10n(.settingsNetworkSection)) {
                Picker(l10n(.settingsDetectionMode), selection: $settings.settings.networkMode) {
                    Text(l10n(.settingsDetectionBySSID)).tag(NetworkMode.bySSID)
                    Text(l10n(.settingsDetectionByIP)).tag(NetworkMode.byIPReachable)
                }
                LabeledContent(l10n(.settingsCurrentNetwork), value: currentSSID)
                TextField(l10n(.settingsSSIDField), text: $settings.settings.ssid)
                TextField(l10n(.settingsModemIPField), text: $settings.settings.modemIP)
            }
            Section(l10n(.settingsStatsSection)) {
                Toggle(l10n(.settingsStatsBasic), isOn: $settings.settings.stats.basic)
                Toggle(l10n(.settingsStatsRadio), isOn: $settings.settings.stats.radio)
                Toggle(l10n(.settingsStatsTransfer), isOn: $settings.settings.stats.transfer)
                Toggle(l10n(.settingsStatsUptime), isOn: $settings.settings.stats.uptime)
            }
            Section(l10n(.settingsAppearanceSection)) {
                Picker(l10n(.settingsLanguage), selection: $settings.settings.language) {
                    Text(l10n(.settingsLanguageSystem)).tag(AppLanguage.system)
                    Text(l10n(.settingsLanguagePolish)).tag(AppLanguage.pl)
                    Text(l10n(.settingsLanguageEnglish)).tag(AppLanguage.en)
                }
            }
            Section(l10n(.settingsAccountSection)) {
                SecureField(l10n(.settingsPasswordField), text: $password)
                HStack {
                    Button(l10n(.settingsSavePassword)) { Keychain.setPassword(password) }
                    Button(l10n(.settingsDeletePassword)) { Keychain.deletePassword(); password = "" }
                }
            }
            Section(l10n(.settingsUpdatesSection)) {
                LabeledContent(l10n(.settingsVersion), value: Self.appVersion)
                Toggle(l10n(.settingsAutoCheck), isOn: $updater.automaticallyChecksForUpdates)
                if updater.automaticallyChecksForUpdates {
                    Picker(l10n(.settingsFrequency), selection: $updater.updateCheckInterval) {
                        Text(l10n(.settingsFrequencyDaily)).tag(TimeInterval(86_400))
                        Text(l10n(.settingsFrequencyWeekly)).tag(TimeInterval(604_800))
                    }
                    Toggle(l10n(.settingsAutoDownload),
                           isOn: $updater.automaticallyDownloadsUpdates)
                }
                HStack {
                    Button(l10n(.settingsCheckNow)) { updater.checkForUpdates() }
                        .disabled(!updater.canCheckForUpdates)
                    Spacer()
                    Text(Self.lastCheckLabel(updater.lastUpdateCheckDate, l10n: l10n))
                        .foregroundStyle(.secondary)
                        .font(.callout)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 380, height: 620)
        .onChange(of: settings.settings.language) { _, new in
            l10n.setLanguage(new)
        }
    }

    static var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
    }

    static func lastCheckLabel(_ date: Date?, l10n: L10n) -> String {
        guard let date else { return l10n(.settingsNeverChecked) }
        let f = RelativeDateTimeFormatter()
        f.locale = l10n.locale
        return l10n(.settingsLastChecked, f.localizedString(for: date, relativeTo: Date()))
    }
}
