import SwiftUI

/// Sparkle update preferences and a manual check.
struct UpdatesSettingsTab: View {
    @Bindable var updater: UpdaterController
    let l10n: L10n

    var body: some View {
        Form {
            Section {
                LabeledContent(l10n(.settingsVersion), value: AppInfo.version)
                LabeledContent(l10n(.settingsBuild), value: AppInfo.build)
            }

            Section {
                Toggle(l10n(.settingsAutoCheck), isOn: $updater.automaticallyChecksForUpdates)
                if updater.automaticallyChecksForUpdates {
                    Picker(l10n(.settingsFrequency), selection: $updater.updateCheckInterval) {
                        Text(l10n(.settingsFrequencyDaily)).tag(TimeInterval(86_400))
                        Text(l10n(.settingsFrequencyWeekly)).tag(TimeInterval(604_800))
                    }
                    Toggle(l10n(.settingsAutoDownload),
                           isOn: $updater.automaticallyDownloadsUpdates)
                }
            }

            Section {
                HStack {
                    Text(Self.lastCheckLabel(updater.lastUpdateCheckDate, l10n: l10n))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button(l10n(.settingsCheckNow)) { updater.checkForUpdates() }
                        .buttonStyle(.borderedProminent)
                        .disabled(!updater.canCheckForUpdates)
                }
            }
        }
        .formStyle(.grouped)
    }

    static func lastCheckLabel(_ date: Date?, l10n: L10n) -> String {
        guard let date else { return l10n(.settingsNeverChecked) }
        let f = RelativeDateTimeFormatter()
        f.locale = l10n.locale
        return l10n(.settingsLastChecked, f.localizedString(for: date, relativeTo: Date()))
    }
}
