import SwiftUI
import Charts

/// RSRP over time. One series, so the pane header names it and no legend is
/// needed; the axis carries the dBm unit. The scale must NOT include zero —
/// RSRP lives around -80…-110 dBm, and anchoring at 0 would squash the line
/// into a flat ribbon at the bottom.
public struct SignalChartView: View {
    let rsrp: [(Date, Int)]

    public init(rsrp: [(Date, Int)]) { self.rsrp = rsrp }

    public var body: some View {
        Chart(Array(rsrp.enumerated()), id: \.offset) { _, point in
            // Double, not Int: the shared axis reads marks back as Double.
            LineMark(x: .value("Time", point.0), y: .value("RSRP", Double(point.1)))
                .foregroundStyle(.teal)
                .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round))
                .interpolationMethod(.monotone)
        }
        .chartYScale(domain: .automatic(includesZero: false))
        .chartXAxis { HistoryChartAxis.time() }
        .chartYAxis { HistoryChartAxis.values { "\(Int($0)) dBm" } }
    }
}
