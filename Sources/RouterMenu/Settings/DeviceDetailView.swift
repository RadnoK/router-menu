import SwiftUI

/// Which slice of a device's settings the detail pane shows. Segments keep
/// the pane short instead of one long scroll; the battery segment exists
/// only for providers whose devices have one.
enum DeviceDetailTab: String, CaseIterable, Identifiable, Sendable {
    case info
    case signIn
    case stats
    case battery

    var id: String { rawValue }

    var titleKey: LocKey {
        switch self {
        case .info: return .settingsDeviceTabInfo
        case .signIn: return .settingsSignInSection
        case .stats: return .settingsDeviceTabStats
        case .battery: return .settingsDeviceTabBattery
        }
    }

    static func available(for provider: ProviderKind) -> [DeviceDetailTab] {
        let capabilities = ProviderCatalog.descriptor(for: provider).capabilities
        return allCases.filter { $0 != .battery || capabilities.hasBattery }
    }
}

/// Everything about ONE device, segmented Mail-style: identity and
/// detection, credentials, popover stats, battery.
struct DeviceDetailView: View {
    @Bindable var settings: SettingsStore
    let l10n: L10n
    let onNotificationsEnabled: () -> Void

    @State private var tab: DeviceDetailTab = .info
    /// Read once at appear: reading CoreWLAN in `body` would hit the Wi-Fi
    /// daemon on every redraw.
    @State private var currentSSID: String?

    private var availableTabs: [DeviceDetailTab] {
        DeviceDetailTab.available(for: settings.profile.provider)
    }

    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $tab) {
                ForEach(availableTabs) { tab in
                    Text(l10n(tab.titleKey)).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.horizontal, 16)
            .padding(.top, 12)

            Form {
                switch availableTabs.contains(tab) ? tab : .info {
                case .info:
                    infoSections
                case .signIn:
                    DeviceSignInSection(settings: settings, l10n: l10n)
                case .stats:
                    statsSection
                case .battery:
                    DeviceBatterySection(settings: settings, l10n: l10n)
                }
            }
            .formStyle(.grouped)
        }
        .task { currentSSID = CoreWLANReader().currentSSID() }
        .onChange(of: settings.profile.provider) { _, newProvider in
            // A provider switch can remove the battery segment from under
            // the selection.
            if !DeviceDetailTab.available(for: newProvider).contains(tab) { tab = .info }
        }
        .onChange(of: settings.profile.batteryNotifications) { old, new in
            guard new.isAnyEnabled, !old.isAnyEnabled else { return }
            onNotificationsEnabled()
        }
    }

    @ViewBuilder
    private var infoSections: some View {
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
    }

    /// Only toggles the device can honour: an Asus router has no radio,
    /// battery, or session counters to chart, so those switches never appear.
    @ViewBuilder
    private var statsSection: some View {
        let capabilities = ProviderCatalog
            .descriptor(for: settings.profile.provider).capabilities
        Section {
            Toggle(l10n(.settingsStatsBasic), isOn: $settings.profile.stats.basic)
            if capabilities.hasRadioSignal {
                Toggle(l10n(.settingsStatsRadio), isOn: $settings.profile.stats.radio)
            }
            Toggle(l10n(.settingsStatsTransfer), isOn: $settings.profile.stats.transfer)
            if capabilities.hasSessionCounters {
                Toggle(l10n(.settingsStatsSession), isOn: $settings.profile.stats.session)
            }
            Toggle(l10n(.settingsStatsUptime), isOn: $settings.profile.stats.uptime)
            Toggle(l10n(.settingsStatsLocalIP), isOn: $settings.profile.stats.localIP)
        } header: {
            Text(l10n(.settingsStatsSection))
        }
        Section {
            Toggle(l10n(.settingsStatsChartTransfer),
                   isOn: $settings.profile.stats.transferChart)
            if capabilities.hasRadioSignal {
                Toggle(l10n(.settingsStatsChartSignal),
                       isOn: $settings.profile.stats.signalChart)
            }
            if capabilities.hasBattery {
                Toggle(l10n(.settingsStatsChartBattery),
                       isOn: $settings.profile.stats.batteryChart)
            }
        } header: {
            Text(l10n(.settingsStatsChartsSection))
        }
    }
}
