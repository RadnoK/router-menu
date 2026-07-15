import SwiftUI
import Charts

public struct BatteryChartView: View {
    let samples: [(Date, Int)]

    public init(samples: [(Date, Int)]) { self.samples = samples }

    public var body: some View {
        Chart(Array(samples.enumerated()), id: \.offset) { _, point in
            AreaMark(x: .value("Czas", point.0), y: .value("Bateria", point.1))
                .foregroundStyle(.green.opacity(0.3))
            LineMark(x: .value("Czas", point.0), y: .value("Bateria", point.1))
                .foregroundStyle(.green)
        }
        .chartYScale(domain: 0...100)
        .chartXAxis(.hidden)
    }
}
