import SwiftUI
import Charts

/// The widget's three layouts.
///
/// Plain SwiftUI with no WidgetKit types, so these render in the test harness
/// and in previews exactly as the extension draws them. Battery leads in every
/// size — it is the reading the widget exists for; signal, transfer and the
/// 24 h chart fill the space each size actually has.
public struct WidgetContentView: View {
    let snapshot: WidgetSnapshot?
    let freshness: WidgetFreshness
    let family: WidgetLayoutFamily
    let now: Date

    public init(snapshot: WidgetSnapshot?, freshness: WidgetFreshness,
                family: WidgetLayoutFamily, now: Date) {
        self.snapshot = snapshot
        self.freshness = freshness
        self.family = family
        self.now = now
    }

    public var body: some View {
        if let snapshot {
            content(snapshot)
                // Stale data stays legible but visibly demoted, so a reading
                // from three hours ago never passes for the current one.
                .opacity(freshness == .stale ? 0.55 : 1)
        } else {
            WidgetEmptyView()
        }
    }

    @ViewBuilder
    private func content(_ s: WidgetSnapshot) -> some View {
        switch family {
        case .small: SmallWidgetView(snapshot: s, freshness: freshness, now: now)
        case .medium: MediumWidgetView(snapshot: s, freshness: freshness, now: now)
        case .large: LargeWidgetView(snapshot: s, freshness: freshness, now: now)
        }
    }
}

/// Mirrors `WidgetFamily` without importing WidgetKit, which keeps every view
/// in this file testable in a plain unit-test process.
public enum WidgetLayoutFamily: CaseIterable {
    case small, medium, large
}

// MARK: - Small

struct SmallWidgetView: View {
    let snapshot: WidgetSnapshot
    let freshness: WidgetFreshness
    let now: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                Image(systemName: WidgetBatteryStyle.symbolName(
                    percent: snapshot.batteryPercent, isCharging: snapshot.isCharging))
                    .foregroundStyle(WidgetBatteryStyle.tint(
                        percent: snapshot.batteryPercent, isCharging: snapshot.isCharging))
                Text(snapshot.deviceName)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            Text(WidgetBatteryStyle.percentText(snapshot.batteryPercent))
                .font(.system(size: 40, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .minimumScaleFactor(0.6)
                .lineLimit(1)
            Spacer(minLength: 0)
            WidgetSignalRow(snapshot: snapshot)
            WidgetFooter(snapshot: snapshot, freshness: freshness, now: now)
        }
    }
}

// MARK: - Medium

struct MediumWidgetView: View {
    let snapshot: WidgetSnapshot
    let freshness: WidgetFreshness
    let now: Date

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 4) {
                    Image(systemName: WidgetBatteryStyle.symbolName(
                        percent: snapshot.batteryPercent, isCharging: snapshot.isCharging))
                        .foregroundStyle(WidgetBatteryStyle.tint(
                            percent: snapshot.batteryPercent, isCharging: snapshot.isCharging))
                    Text(snapshot.deviceName)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                Text(WidgetBatteryStyle.percentText(snapshot.batteryPercent))
                    .font(.system(size: 44, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                Spacer(minLength: 0)
                WidgetFooter(snapshot: snapshot, freshness: freshness, now: now)
            }
            Divider()
            VStack(alignment: .leading, spacing: 8) {
                WidgetSignalRow(snapshot: snapshot)
                WidgetSignalDetail(snapshot: snapshot)
                Divider()
                WidgetTransferRows(snapshot: snapshot)
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

// MARK: - Large

struct LargeWidgetView: View {
    let snapshot: WidgetSnapshot
    let freshness: WidgetFreshness
    let now: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 8) {
                Image(systemName: WidgetBatteryStyle.symbolName(
                    percent: snapshot.batteryPercent, isCharging: snapshot.isCharging))
                    // Scaled to the headline number beside it: at body size the
                    // glyph sat level with the digits' baseline and read as an
                    // afterthought under them.
                    .font(.title2)
                    .foregroundStyle(WidgetBatteryStyle.tint(
                        percent: snapshot.batteryPercent, isCharging: snapshot.isCharging))
                Text(WidgetBatteryStyle.percentText(snapshot.batteryPercent))
                    .font(.system(size: 46, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                Spacer(minLength: 0)
                VStack(alignment: .trailing, spacing: 2) {
                    Text(snapshot.deviceName)
                        .font(.caption)
                        .lineLimit(1)
                    WidgetSignalRow(snapshot: snapshot)
                }
            }
            if snapshot.batteryHistory.isEmpty {
                // No history yet (fresh install, or the app has only just
                // started): an empty chart frame reads as a broken widget, so
                // say what is happening instead.
                WidgetChartPlaceholder()
            } else {
                WidgetBatteryHistoryChart(points: snapshot.batteryHistory)
                    .frame(maxHeight: .infinity)
                    // The trailing Y labels sit outside the plot, which pushed
                    // the final X label off the edge and rendered it as "0".
                    .padding(.trailing, 4)
            }
            Divider()
            HStack(alignment: .top, spacing: 16) {
                WidgetSignalDetail(snapshot: snapshot)
                Spacer(minLength: 0)
                WidgetTransferRows(snapshot: snapshot)
            }
            WidgetFooter(snapshot: snapshot, freshness: freshness, now: now)
        }
    }
}

// MARK: - Shared pieces

struct WidgetSignalRow: View {
    let snapshot: WidgetSnapshot

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: WidgetBatteryStyle.signalSymbol(bars: snapshot.signalBars))
                .foregroundStyle(snapshot.isOnline ? .primary : .secondary)
            Text(snapshot.networkLabel)
                .font(.caption)
                .foregroundStyle(snapshot.isOnline ? .primary : .secondary)
        }
        .lineLimit(1)
    }
}

struct WidgetSignalDetail: View {
    let snapshot: WidgetSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            if let rsrp = snapshot.rsrp {
                WidgetStatLine(label: "RSRP", value: "\(rsrp) dBm")
            }
            if let sinr = snapshot.sinr {
                WidgetStatLine(label: "SINR", value: String(format: "%.1f dB", sinr))
            }
        }
    }
}

struct WidgetTransferRows: View {
    let snapshot: WidgetSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            if let rx = snapshot.rxSpeed {
                WidgetStatLine(label: "↓", value: ByteFormat.speed(rx))
            }
            if let tx = snapshot.txSpeed {
                WidgetStatLine(label: "↑", value: ByteFormat.speed(tx))
            }
            if let sessionRx = snapshot.sessionRx, let sessionTx = snapshot.sessionTx {
                WidgetStatLine(label: "Σ", value: ByteFormat.bytes(sessionRx + sessionTx))
            }
        }
    }
}

struct WidgetStatLine: View {
    let label: String
    let value: String

    var body: some View {
        HStack(spacing: 4) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.caption2)
                .monospacedDigit()
        }
        .lineLimit(1)
    }
}

struct WidgetBatteryHistoryChart: View {
    let points: [WidgetSnapshot.Point]

    var body: some View {
        Chart(Array(points.enumerated()), id: \.offset) { _, point in
            AreaMark(x: .value("Time", point.t), y: .value("Battery", point.v))
                .foregroundStyle(.green.opacity(0.2))
                .interpolationMethod(.monotone)
            LineMark(x: .value("Time", point.t), y: .value("Battery", point.v))
                .foregroundStyle(.green)
                .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round))
                .interpolationMethod(.monotone)
        }
        .chartYScale(domain: 0...100)
        // Explicit ticks, inset from both edges: see `WidgetChartTicks`.
        .chartXAxis {
            AxisMarks(values: WidgetChartTicks.dates(from: points)) { value in
                AxisGridLine()
                AxisValueLabel {
                    if let date = value.as(Date.self) {
                        Text(date, format: .dateTime.hour().minute()).font(.caption2)
                    }
                }
            }
        }
        .chartYAxis {
            AxisMarks(position: .trailing, values: [0, 50, 100]) { value in
                AxisGridLine()
                AxisValueLabel {
                    if let v = value.as(Int.self) {
                        Text("\(v)%").font(.caption2).monospacedDigit()
                    }
                }
            }
        }
    }
}

struct WidgetChartPlaceholder: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 6)
            .fill(.quaternary)
            .overlay {
                Text(WidgetCopy.noHistoryYet)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .frame(maxHeight: .infinity)
    }
}

/// The line that keeps the widget honest about *when* the reading is from.
struct WidgetFooter: View {
    let snapshot: WidgetSnapshot
    let freshness: WidgetFreshness
    let now: Date

    var body: some View {
        Group {
            switch freshness {
            case .fresh:
                // Nothing to disclose: the reading is current, and a timestamp
                // here would only compete with the number above it.
                EmptyView()
            case .aging, .stale:
                Text(WidgetAgeText.string(capturedAt: snapshot.capturedAt, now: now))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }
}

/// Shown when no snapshot exists at all: a fresh install, the app never
/// launched, or the modem is out of range and the app cleared the file.
struct WidgetEmptyView: View {
    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: "antenna.radiowaves.left.and.right.slash")
                .font(.title2)
                .foregroundStyle(.secondary)
            Text(WidgetCopy.noData)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
