import SwiftUI

/// Battery percentage in the menu bar, and the alerts fired as the battery
/// drains — shown only for providers whose devices have a battery.
struct DeviceBatterySection: View {
    @Bindable var settings: SettingsStore
    let l10n: L10n
    // Note: the notification-permission hook lives in DeviceDetailView's
    // .onChange, which wraps this whole section — no callback needed here.

    private var alerts: BatteryNotificationSettings {
        settings.profile.batteryNotifications
    }

    var body: some View {
        Section {
            Toggle(l10n(.settingsBatteryShowPercent), isOn: $settings.profile.showBatteryPercent)
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
                settings.profile.batteryNotifications
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
                set: { settings.profile.batteryNotifications.fullEnabled = $0 }
            ))
        } header: {
            Text(l10n(.settingsBatteryNotificationsSection))
        }
    }

    /// One threshold: armed or not, at what level, and how loudly.
    ///
    /// Every control writes through the model's validating methods rather than
    /// binding into the array directly — a percentage that collides with
    /// another row has to be rejected, not stored.
    @ViewBuilder
    private func thresholdRow(_ threshold: BatteryThreshold) -> some View {
        // `.firstTextBaseline`, not the default centre: these controls have
        // different heights, so centring them lines up their boxes while their
        // text drifts apart. The baseline is what the eye actually reads.
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Toggle("", isOn: Binding(
                get: { threshold.isEnabled },
                set: { settings.profile.batteryNotifications
                        .updateThreshold(id: threshold.id, isEnabled: $0) }
            ))
            .labelsHidden()

            Text(l10n(.settingsBatteryThreshold, threshold.percent))
                .monospacedDigit()

            Spacer(minLength: 8)

            // The stepper's own label is left empty: inside a Form, macOS
            // treats it as the row's form label and moves it to the leading
            // column, which would tear the text away from its controls.
            Stepper("", value: Binding(
                get: { threshold.percent },
                set: { settings.profile.batteryNotifications
                        .updateThreshold(id: threshold.id, percent: $0) }
            ), in: BatteryNotificationSettings.percentRange)
            .labelsHidden()

            Picker("", selection: Binding(
                get: { threshold.isUrgent },
                set: { settings.profile.batteryNotifications
                        .updateThreshold(id: threshold.id, isUrgent: $0) }
            )) {
                Text(l10n(.settingsBatteryNormal)).tag(false)
                Text(l10n(.settingsBatteryUrgent)).tag(true)
            }
            .labelsHidden()
            .fixedSize()

            Button {
                settings.profile.batteryNotifications.removeThreshold(id: threshold.id)
            } label: {
                Image(systemName: "minus.circle")
            }
            .buttonStyle(.borderless)
            .help(l10n(.settingsBatteryRemoveThreshold))
        }
    }
}
