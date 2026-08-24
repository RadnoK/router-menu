import SwiftUI

public struct PopoverView: View {
    @State private var store: ModemStore
    private let settings: SettingsStore
    private let l10n: L10n
    private let openSettings: () -> Void

    public init(store: ModemStore,
                settings: SettingsStore,
                l10n: L10n,
                openSettings: @escaping () -> Void) {
        _store = State(initialValue: store)
        self.settings = settings
        self.l10n = l10n
        self.openSettings = openSettings
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            content
            Divider()
            footer
        }
        .padding(14)
        .frame(width: 320)
    }

    @ViewBuilder
    private var content: some View {
        switch store.state {
        case .hidden:
            label(l10n(.popoverNoConnection), "wifi.slash")
        case .locationDenied:
            label(l10n(.popoverLocationDenied), "location.slash")
        case .error(let kind):
            label(l10n(Self.key(for: kind)), "exclamationmark.triangle")
        case .connected(let d):
            connected(d, profile: settings.settings.profile(with: store.activeProfile?.id)
                ?? store.activeProfile
                ?? settings.profile)
        }
    }

    // MARK: Pane visibility

    /// Which panes a profile's toggles and the available data earn. Static
    /// and pure so the composition rules are testable without rendering.
    static func showsStatusPane(stats: StatVisibility) -> Bool {
        stats.basic || stats.uptime
    }

    static func showsSignalPane(stats: StatVisibility, hasRadio: Bool,
                                hasChartData: Bool) -> Bool {
        hasRadio && (stats.radio || (stats.signalChart && hasChartData))
    }

    static func showsTransferPane(stats: StatVisibility, hasChartData: Bool) -> Bool {
        stats.transfer || stats.session || (stats.transferChart && hasChartData)
    }

    static func showsBatteryPane(stats: StatVisibility, hasBattery: Bool,
                                 hasChartData: Bool) -> Bool {
        hasBattery && stats.batteryChart && hasChartData
    }

    // MARK: Connected layout

    @ViewBuilder
    private func connected(_ d: ModemData, profile: ModemProfile) -> some View {
        let caps = ProviderCatalog.descriptor(for: profile.provider).capabilities
        let rsrpSeries = store.history.rsrpSeries()
        let downloadSeries = store.history.downloadSpeedSeries()
        let batterySeries = store.history.batterySeries()
        // "Radio" here means "has radio values to show", not just the
        // capability — a ZTE camped on LTE reports no 5G RSRP, and a pane
        // holding only a header would be noise.
        let hasRadioNow = caps.hasRadioSignal
            && (d.rsrp != nil || d.sinr != nil || rsrpSeries.count >= 2)

        VStack(alignment: .leading, spacing: 2) {
            Text(Self.headerText(for: profile))
                .font(.headline)
            if let p = d.provider {
                Text("\(p) · \(d.networkLabel)")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }

        if Self.showsStatusPane(stats: profile.stats) {
            pane(l10n(.popoverSectionStatus)) {
                if profile.stats.basic {
                    statusRows(d, capabilities: caps)
                }
                if profile.stats.uptime, let up = d.sessionUptime {
                    row("timer", l10n(.popoverSession), ByteFormat.uptime(up))
                }
            }
        }

        if Self.showsSignalPane(stats: profile.stats, hasRadio: hasRadioNow,
                                hasChartData: rsrpSeries.count >= 2) {
            pane(l10n(.popoverSectionSignal)) {
                if profile.stats.radio {
                    radioRows(d)
                }
                if profile.stats.signalChart, rsrpSeries.count >= 2 {
                    SignalChartView(rsrp: rsrpSeries)
                        .frame(height: 56)
                }
            }
        }

        if Self.showsTransferPane(stats: profile.stats,
                                  hasChartData: downloadSeries.count >= 2) {
            pane(l10n(.popoverSectionTransfer)) {
                if profile.stats.transfer {
                    transferRows(d)
                }
                if profile.stats.session, caps.hasSessionCounters,
                   let sessionRx = d.sessionRx, let sessionTx = d.sessionTx {
                    row("clock.arrow.circlepath", l10n(.popoverSessionData),
                        ByteFormat.bytes(sessionRx + sessionTx))
                }
                if profile.stats.transferChart, downloadSeries.count >= 2 {
                    TransferChartView(download: downloadSeries,
                                      upload: store.history.uploadSpeedSeries(),
                                      downloadLabel: l10n(.popoverDownload),
                                      uploadLabel: l10n(.popoverUpload))
                        .frame(height: 88)
                }
            }
        }

        if Self.showsBatteryPane(stats: profile.stats, hasBattery: caps.hasBattery,
                                 hasChartData: batterySeries.count >= 2) {
            pane(l10n(.popoverSectionBattery)) {
                BatteryChartView(samples: batterySeries)
                    .frame(height: 56)
            }
        }
    }

    // MARK: Rows

    @ViewBuilder
    private func statusRows(_ d: ModemData, capabilities: ModemCapabilities) -> some View {
        if let b = d.batteryPercent {
            row(batterySymbol(b, d.isCharging), l10n(.popoverBattery),
                "\(b)%\(d.isCharging ? " ⚡" : "")")
        }
        if capabilities.hasRadioSignal {
            row("cellularbars", l10n(.popoverSignal),
                "\(l10n(Self.key(for: d.signalQuality))) (\(d.signalBars)/5)")
        }
        row("antenna.radiowaves.left.and.right", l10n(.popoverNetwork), d.networkLabel)
    }

    @ViewBuilder
    private func radioRows(_ d: ModemData) -> some View {
        if let r = d.rsrp { row("waveform.path", "RSRP", "\(r) dBm") }
        if let s = d.sinr { row("waveform", "SINR", "\(Int(s)) dB") }
    }

    @ViewBuilder
    private func transferRows(_ d: ModemData) -> some View {
        if let rx = d.rxSpeed, let tx = d.txSpeed {
            row("arrow.down.circle", l10n(.popoverDownload), ByteFormat.speed(rx))
            row("arrow.up.circle", l10n(.popoverUpload), ByteFormat.speed(tx))
        }
        if let mrx = d.monthlyRx, let mtx = d.monthlyTx {
            row("calendar", l10n(.popoverMonthly), "\(ByteFormat.gb(mrx + mtx))")
        }
        if let trx = d.totalRx, let ttx = d.totalTx {
            row("sum", l10n(.popoverTotal), "\(ByteFormat.gb(trx + ttx))")
        }
    }

    // MARK: Building blocks

    /// One bordered box per topic, so charts and rows never run into the
    /// neighbouring section's text.
    private func pane<Content: View>(_ title: String,
                                     @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            content()
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quinary, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    /// Symbols differ in intrinsic width (`cellularbars` is far narrower than
    /// `battery.100`), which would ragged-edge every title in the list. A fixed
    /// centred slot keeps the text baseline aligned without adding a gap.
    private static let iconWidth: CGFloat = 18

    private func icon(_ symbol: String) -> some View {
        Image(systemName: symbol)
            .symbolRenderingMode(.monochrome)
            .frame(width: Self.iconWidth, alignment: .center)
    }

    private func row(_ symbol: String, _ title: String, _ value: String) -> some View {
        HStack(spacing: 6) {
            icon(symbol)
            Text(title)
            Spacer()
            Text(value).foregroundStyle(.primary).monospacedDigit()
        }
        .font(.callout)
    }

    private func label(_ text: String, _ symbol: String) -> some View {
        HStack(spacing: 6) {
            icon(symbol)
            Text(text)
        }
        .foregroundStyle(.secondary)
    }

    private var footer: some View {
        HStack {
            Button { Task { await store.refresh() } } label: {
                Label(l10n(.popoverRefresh), systemImage: "arrow.clockwise")
            }
            Spacer()
            Button { openSettings() } label: {
                Label(l10n(.popoverSettings), systemImage: "gearshape")
            }
            Button { NSApplication.shared.terminate(nil) } label: {
                Label(l10n(.popoverQuit), systemImage: "power")
            }
        }
        .labelStyle(.iconOnly)
        .buttonStyle(.borderless)
    }

    private func batterySymbol(_ percent: Int, _ charging: Bool) -> String {
        if charging { return "battery.100.bolt" }
        switch percent {
        case ...10: return "battery.0"
        case ...35: return "battery.25"
        case ...60: return "battery.50"
        case ...85: return "battery.75"
        default: return "battery.100"
        }
    }

    static func key(for quality: SignalQuality) -> LocKey {
        switch quality {
        case .noSignal: return .signalNone
        case .veryWeak: return .signalVeryWeak
        case .weak: return .signalWeak
        case .medium: return .signalMedium
        case .good: return .signalGood
        case .veryGood: return .signalVeryGood
        }
    }

    static func key(for error: ModemErrorKind) -> LocKey {
        switch error {
        case .loginFailed: return .errorLoginFailed
        case .unreachable: return .errorUnreachable
        }
    }

    static func headerText(for profile: ModemProfile) -> String {
        profile.displayTitle
    }
}
