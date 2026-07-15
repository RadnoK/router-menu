import SwiftUI
import Charts

public struct TransferChartView: View {
    let download: [(Date, Double)]

    public init(download: [(Date, Double)]) { self.download = download }

    public var body: some View {
        Chart(Array(download.enumerated()), id: \.offset) { _, point in
            LineMark(x: .value("Czas", point.0), y: .value("B/s", point.1))
                .foregroundStyle(.blue)
        }
        .chartXAxis(.hidden)
    }
}
