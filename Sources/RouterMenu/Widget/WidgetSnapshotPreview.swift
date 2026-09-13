import Foundation

/// Believable values for the widget gallery and SwiftUI previews.
///
/// The gallery renders before any App Group data exists, and an empty frame
/// there reads as a broken widget — this is what the user sees when deciding
/// whether to add it at all.
public enum WidgetSnapshotPreview {
    public static var sample: WidgetSnapshot {
        let now = Date()
        let history: [(Date, Double)] = (0..<144).map { i in
            (now.addingTimeInterval(Double(i - 144) * 600), max(20, 92 - Double(i) * 0.45))
        }
        return WidgetSnapshot(capturedAt: now,
                              deviceName: "ZTE U50",
                              batteryPercent: 61,
                              isCharging: false,
                              signalBars: 4,
                              networkLabel: "5G",
                              rsrp: -93,
                              sinr: 12.4,
                              rxSpeed: 5_871_000,
                              txSpeed: 912_000,
                              sessionRx: 1_008_395_299,
                              sessionTx: 350_536_546,
                              batteryHistory: WidgetHistoryDownsample.reduce(history),
                              isOnline: true)
    }
}
