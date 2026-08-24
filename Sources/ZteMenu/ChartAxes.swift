import SwiftUI
import Charts

/// Shared axis styling for the popover's history charts, so every chart
/// reads the same way: a few time ticks on X, a few UNIT-LABELLED marks on
/// Y. The default numeric axis renders large byte counts in scientific
/// notation ("5E7"), which is exactly what these formatters exist to avoid.
enum HistoryChartAxis {
    @AxisContentBuilder
    static func time() -> some AxisContent {
        AxisMarks(values: .automatic(desiredCount: 3)) { value in
            AxisGridLine()
            AxisValueLabel {
                if let date = value.as(Date.self) {
                    Text(date, format: .dateTime.hour().minute())
                        .font(.caption2)
                }
            }
        }
    }

    @AxisContentBuilder
    static func values(_ format: @escaping (Double) -> String) -> some AxisContent {
        AxisMarks(position: .trailing, values: .automatic(desiredCount: 3)) { value in
            AxisGridLine()
            AxisValueLabel {
                if let v = value.as(Double.self) {
                    Text(format(v))
                        .font(.caption2)
                        .monospacedDigit()
                }
            }
        }
    }
}
