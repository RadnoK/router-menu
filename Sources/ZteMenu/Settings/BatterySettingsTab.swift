import SwiftUI

/// Battery percentage in the menu bar, and the alerts fired as the modem's
/// battery drains — a list the user builds themselves.
struct BatterySettingsTab: View {
    @Bindable var settings: SettingsStore
    let l10n: L10n
    /// Asked for notification permission when an alert is armed — the prompt
    /// then arrives with the context that explains it.
    let onNotificationsEnabled: () -> Void

    private var alerts: BatteryNotificationSettings {
        settings.settings.batteryNotifications
    }

    var body: some View {
        Form {
            Section {
                Toggle(l10n(.settingsBatteryShowPercent), isOn: $settings.settings.showBatteryPercent)
                    .help(l10n(.settingsBatteryShowPercentHelp))
            } header: {
                Text(l10n(.settingsBatteryMenuBarSection))
            }

            Section {
                if alerts.thresholds.isEmpty {
                    Text(l10n(.settingsBatteryNoThresholds))
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(alerts.thresholds) { threshold in
                        thresholdRow(threshold)
                    }
                }
                Button(l10n(.settingsBatteryAddThreshold), systemImage: "plus") {
                    settings.settings.batteryNotifications
                        .addThreshold(percent: alerts.suggestedNewThreshold)
                }
                .disabled(alerts.thresholds.count >= BatteryNotificationSettings.percentRange.count)
            } header: {
                Text(l10n(.settingsBatteryThresholdsSection))
            } footer: {
                Text(l10n(.settingsBatteryNotificationsHelp))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section {
                Toggle(l10n(.settingsBatteryFull), isOn: Binding(
                    get: { alerts.fullEnabled },
                    set: { settings.settings.batteryNotifications.fullEnabled = $0 }
                ))
            } header: {
                Text(l10n(.settingsBatteryNotificationsSection))
            }
        }
        .formStyle(.grouped)
        .onChange(of: alerts) { old, new in
            guard new.isAnyEnabled, !old.isAnyEnabled else { return }
            onNotificationsEnabled()
        }
    }

    /// One threshold: armed or not, at what level, and how loudly.
    ///
    /// Every control writes through the model's validating methods rather than
    /// binding into the array directly — a percentage that collides with
    /// another row has to be rejected, not stored.
    @ViewBuilder
    private func thresholdRow(_ threshold: BatteryThreshold) -> some View {
        HStack(spacing: 10) {
            Toggle("", isOn: Binding(
                get: { threshold.isEnabled },
                set: { settings.settings.batteryNotifications
                        .updateThreshold(id: threshold.id, isEnabled: $0) }
            ))
            .labelsHidden()

            Stepper(value: Binding(
                get: { threshold.percent },
                set: { settings.settings.batteryNotifications
                        .updateThreshold(id: threshold.id, percent: $0) }
            ), in: BatteryNotificationSettings.percentRange) {
                Text(l10n(.settingsBatteryThreshold, threshold.percent))
                    .monospacedDigit()
            }

            Picker("", selection: Binding(
                get: { threshold.isUrgent },
                set: { settings.settings.batteryNotifications
                        .updateThreshold(id: threshold.id, isUrgent: $0) }
            )) {
                Text(l10n(.settingsBatteryNormal)).tag(false)
                Text(l10n(.settingsBatteryUrgent)).tag(true)
            }
            .labelsHidden()
            .fixedSize()

            Button {
                settings.settings.batteryNotifications.removeThreshold(id: threshold.id)
            } label: {
                Image(systemName: "minus.circle")
            }
            .buttonStyle(.borderless)
            .help(l10n(.settingsBatteryRemoveThreshold))
        }
    }
}
