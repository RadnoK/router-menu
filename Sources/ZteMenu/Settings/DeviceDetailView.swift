import SwiftUI

/// Everything about ONE device: identity, detection, credentials, and the
/// per-device presentation preferences that used to be their own tabs.
struct DeviceDetailView: View {
    @Bindable var settings: SettingsStore
    let l10n: L10n
    let onNotificationsEnabled: () -> Void

    /// Read once at appear: reading CoreWLAN in `body` would hit the Wi-Fi
    /// daemon on every redraw.
    @State private var currentSSID: String?

    private var capabilities: ModemCapabilities {
        ProviderCatalog.descriptor(for: settings.profile.provider).capabilities
    }

    var body: some View {
        Form {
            Section {
                TextField(l10n(.settingsDeviceName),
                          text: $settings.profile.name,
                          prompt: Text(settings.profile.displayTitle))
                Picker(l10n(.settingsDeviceType), selection: Binding(
                    get: { settings.profile.provider },
                    set: { settings.profile = settings.profile.adopting(provider: $0) }
                )) {
                    ForEach(ProviderKind.allCases, id: \.self) { kind in
                        Text(ProviderCatalog.descriptor(for: kind).displayName).tag(kind)
                    }
                }
            }

            Section {
                Picker(l10n(.settingsDetectionMode), selection: $settings.profile.matchMode) {
                    ForEach(ProviderCatalog.descriptor(for: settings.profile.provider)
                                .supportedMatchModes, id: \.self) { mode in
                        Text(l10n(mode == .ssid ? .settingsDetectionBySSID
                                                : .settingsDetectionByIP)).tag(mode)
                    }
                }
                LabeledContent(l10n(.settingsCurrentNetwork),
                               value: currentSSID ?? l10n(.placeholderDash))
                if settings.profile.matchMode == .ssid {
                    TextField(l10n(.settingsSSIDField), text: $settings.profile.ssid)
                        .help(l10n(.settingsSSIDHelp))
                } else {
                    TextField(l10n(.settingsModemIPField), text: $settings.profile.modemIP)
                        .help(l10n(.settingsModemIPHelp))
                }
            }

            DeviceSignInSection(settings: settings, l10n: l10n)

            Section {
                Toggle(l10n(.settingsStatsBasic), isOn: $settings.profile.stats.basic)
                Toggle(l10n(.settingsStatsRadio), isOn: $settings.profile.stats.radio)
                Toggle(l10n(.settingsStatsTransfer), isOn: $settings.profile.stats.transfer)
                Toggle(l10n(.settingsStatsUptime), isOn: $settings.profile.stats.uptime)
            } header: {
                Text(l10n(.settingsStatsSection))
            }

            if capabilities.hasBattery {
                DeviceBatterySection(settings: settings, l10n: l10n)
            }
        }
        .formStyle(.grouped)
        .task { currentSSID = CoreWLANReader().currentSSID() }
        .onChange(of: settings.profile.batteryNotifications) { old, new in
            guard new.isAnyEnabled, !old.isAnyEnabled else { return }
            onNotificationsEnabled()
        }
    }
}
