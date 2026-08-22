import SwiftUI

/// Battery percentage in the menu bar, and the alerts fired as the modem's
/// battery drains.
struct BatterySettingsTab: View {
    @Bindable var settings: SettingsStore
    let l10n: L10n
    /// Asked for notification permission when an alert is armed — the prompt
    /// then arrives with the context that explains it, rather than at launch.
    let onNotificationsEnabled: () -> Void

    private var alerts: Binding<BatteryNotificationSettings> {
        $settings.settings.batteryNotifications
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
                thresholdRow(title: l10n(.settingsBatteryLow),
                             isOn: alerts.lowEnabled,
                             threshold: alerts.lowThreshold,
                             isCritical: false)
                thresholdRow(title: l10n(.settingsBatteryCritical),
                             isOn: alerts.criticalEnabled,
                             threshold: alerts.criticalThreshold,
                             isCritical: true)
                Toggle(l10n(.settingsBatteryFull), isOn: alerts.fullEnabled)
            } header: {
                Text(l10n(.settingsBatteryNotificationsSection))
            } footer: {
                Text(l10n(.settingsBatteryNotificationsHelp))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .onChange(of: settings.settings.batteryNotifications) { old, new in
            guard new.isAnyEnabled, !old.isAnyEnabled else { return }
            onNotificationsEnabled()
        }
    }

    /// A toggle plus its threshold stepper. The stepper is disabled rather than
    /// hidden so the row keeps its height as the toggle flips.
    @ViewBuilder
    private func thresholdRow(title: String,
                              isOn: Binding<Bool>,
                              threshold: Binding<Int>,
                              isCritical: Bool) -> some View {
        Toggle(title, isOn: isOn)
        Stepper(value: threshold,
                in: BatteryNotificationSettings.thresholdRange,
                step: BatteryNotificationSettings.thresholdStep) {
            Text(l10n(.settingsBatteryThreshold, threshold.wrappedValue))
        }
        .disabled(!isOn.wrappedValue)
        .onChange(of: threshold.wrappedValue) { _, _ in
            settings.settings.batteryNotifications.resolveThresholdOverlap(movedCritical: isCritical)
        }
    }
}
