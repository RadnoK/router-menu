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
        VStack(alignment: .leading, spacing: 12) {
            content
            Divider()
            footer
        }
        .padding(14)
        .frame(width: 300)
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

    @ViewBuilder
    private func connected(_ d: ModemData, profile: ModemProfile) -> some View {
        Text(Self.headerText(for: profile))
            .font(.headline)
        if let p = d.provider {
            Text("\(p) · \(d.networkLabel)").foregroundStyle(.secondary)
        }
        if profile.stats.basic {
            statSection(d)
        }
        if profile.stats.radio {
            radioSection(d)
        }
        if profile.stats.transfer {
            transferSection(d)
        }
        if profile.stats.uptime, let up = d.sessionUptime {
            row("timer", l10n(.popoverSession), ByteFormat.uptime(up))
        }
        if !store.history.batterySeries().isEmpty {
            BatteryChartView(samples: store.history.batterySeries())
                .frame(height: 60)
        }
    }

    @ViewBuilder
    private func statSection(_ d: ModemData) -> some View {
        if let b = d.batteryPercent {
            row(batterySymbol(b, d.isCharging), l10n(.popoverBattery),
                "\(b)%\(d.isCharging ? " ⚡" : "")")
        }
        row("cellularbars", l10n(.popoverSignal),
            "\(l10n(Self.key(for: d.signalQuality))) (\(d.signalBars)/5)")
        row("antenna.radiowaves.left.and.right", l10n(.popoverNetwork), d.networkLabel)
    }

    @ViewBuilder
    private func radioSection(_ d: ModemData) -> some View {
        if let r = d.rsrp { row("waveform.path", "RSRP", "\(r) dBm") }
        if let s = d.sinr { row("waveform", "SINR", "\(Int(s)) dB") }
    }

    @ViewBuilder
    private func transferSection(_ d: ModemData) -> some View {
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
        let downloadSeries = store.history.downloadSpeedSeries()
        if !downloadSeries.isEmpty {
            // HistoryStore.downloadSpeedSeries() can emit negative values when the
            // modem's byte counter resets (e.g. reboot) — clamp in the view layer
            // rather than touching the tested HistoryStore logic.
            TransferChartView(download: downloadSeries.map { ($0.0, max(0, $0.1)) })
                .frame(height: 60)
        }
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

    /// "ZTE · ZTE_B4B622" — the provider's brand plus whichever identifier
    /// the profile matches by. Pure so the header is unit-testable.
    static func headerText(for profile: ModemProfile) -> String {
        let name = ProviderCatalog.descriptor(for: profile.provider).displayName
        let identifier = profile.matchMode == .ssid ? profile.ssid : profile.modemIP
        return "\(name) · \(identifier)"
    }
}
