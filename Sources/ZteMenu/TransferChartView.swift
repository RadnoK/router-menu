import SwiftUI
import Charts

/// Download and upload as two fixed-colour line series on one byte-rate
/// axis. Colour follows the entity everywhere — download is always blue,
/// upload always orange (a colourblind-safe pair) — and the legend carries
/// the localized names, so identity never rides on colour alone.
public struct TransferChartView: View {
    let download: [(Date, Double)]
    let upload: [(Date, Double)]
    let downloadLabel: String
    let uploadLabel: String

    public init(download: [(Date, Double)], upload: [(Date, Double)],
                downloadLabel: String, uploadLabel: String) {
        self.download = download
        self.upload = upload
        self.downloadLabel = downloadLabel
        self.uploadLabel = uploadLabel
    }

    public var body: some View {
        Chart {
            series(download, name: downloadLabel)
            series(upload, name: uploadLabel)
        }
        .chartForegroundStyleScale(domain: [downloadLabel, uploadLabel],
                                   range: [Color.blue, Color.orange])
        .chartLegend(position: .bottom, alignment: .leading, spacing: 4)
        .chartXAxis { HistoryChartAxis.time() }
        .chartYAxis { HistoryChartAxis.values { ByteFormat.speed($0) } }
    }

    @ChartContentBuilder
    private func series(_ points: [(Date, Double)], name: String) -> some ChartContent {
        ForEach(Array(points.enumerated()), id: \.offset) { _, point in
            LineMark(x: .value("Time", point.0),
                     y: .value("Speed", point.1),
                     series: .value("Series", name))
                .foregroundStyle(by: .value("Series", name))
                .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round))
                .interpolationMethod(.monotone)
        }
    }
}
