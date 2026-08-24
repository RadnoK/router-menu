import SwiftUI
import Charts

/// Battery level over time on a fixed 0–100 % scale, so a half-full battery
/// looks half full regardless of how much the level moved.
public struct BatteryChartView: View {
    let samples: [(Date, Int)]

    public init(samples: [(Date, Int)]) { self.samples = samples }

    public var body: some View {
        Chart(Array(samples.enumerated()), id: \.offset) { _, point in
            AreaMark(x: .value("Time", point.0), y: .value("Battery", point.1))
                .foregroundStyle(.green.opacity(0.2))
                .interpolationMethod(.monotone)
            LineMark(x: .value("Time", point.0), y: .value("Battery", point.1))
                .foregroundStyle(.green)
                .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round))
                .interpolationMethod(.monotone)
        }
        .chartYScale(domain: 0...100)
        .chartXAxis { HistoryChartAxis.time() }
        .chartYAxis {
            AxisMarks(position: .trailing, values: [0, 50, 100]) { value in
                AxisGridLine()
                AxisValueLabel {
                    if let v = value.as(Int.self) {
                        Text("\(v)%")
                            .font(.caption2)
                            .monospacedDigit()
                    }
                }
            }
        }
    }
}
