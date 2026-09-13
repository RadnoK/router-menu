import Foundation

/// Hands a fresh reading to the widget process.
///
/// A protocol rather than a direct `WidgetCenter` call so `ModemStore` stays
/// testable: the real implementation reloads timelines, which in a unit test
/// would reach into WidgetKit and either no-op noisily or fail outright.
@MainActor
protocol WidgetPublishing {
    func publish(_ snapshot: WidgetSnapshot)
    /// The modem went away (out of range, app quit). The widget must stop
    /// showing a reading that is no longer backed by anything.
    func clear()
}

/// Builds the snapshot from the live model and the 24 h history.
///
/// Kept apart from `ModemStore` because the mapping — which fields the widget
/// sees, how the chart series is thinned — is worth testing on its own, and
/// because the store already carries enough responsibility.
@MainActor
struct WidgetSnapshotBuilder {
    static func make(from data: ModemData,
                     profile: ModemProfile,
                     history: HistoryStore,
                     now: Date = Date()) -> WidgetSnapshot {
        WidgetSnapshot(capturedAt: now,
                       deviceName: profile.name,
                       batteryPercent: data.batteryPercent,
                       isCharging: data.isCharging,
                       signalBars: data.signalBars,
                       networkLabel: data.networkLabel,
                       rsrp: data.rsrp,
                       sinr: data.sinr,
                       rxSpeed: data.rxSpeed,
                       txSpeed: data.txSpeed,
                       sessionRx: data.sessionRx,
                       sessionTx: data.sessionTx,
                       batteryHistory: WidgetHistoryDownsample.reduce(
                           history.batterySeries().map { ($0.0, Double($0.1)) }),
                       isOnline: data.isOnline)
    }
}
