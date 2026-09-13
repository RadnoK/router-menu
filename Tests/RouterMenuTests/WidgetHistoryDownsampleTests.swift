import XCTest
@testable import RouterMenu

final class WidgetHistoryDownsampleTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_700_000_000)

    private func evenSeries(count: Int, step: TimeInterval = 60,
                            value: (Int) -> Double = { Double($0) }) -> [(Date, Double)] {
        (0..<count).map { (start.addingTimeInterval(Double($0) * step), value($0)) }
    }

    func testEmptySeriesGivesNoPoints() {
        XCTAssertTrue(WidgetHistoryDownsample.reduce([]).isEmpty)
    }

    func testShortSeriesPassesThroughUntouched() {
        let series = evenSeries(count: 10)
        let result = WidgetHistoryDownsample.reduce(series)
        XCTAssertEqual(result.count, 10)
        XCTAssertEqual(result.map(\.v), series.map(\.1))
    }

    func testSeriesAtTheLimitIsNotReduced() {
        let result = WidgetHistoryDownsample.reduce(evenSeries(count: 144))
        XCTAssertEqual(result.count, 144)
    }

    func testLongSeriesIsCappedAtTheLimit() {
        let result = WidgetHistoryDownsample.reduce(evenSeries(count: 1440))
        XCTAssertLessThanOrEqual(result.count, WidgetHistoryDownsample.maxPoints)
        XCTAssertGreaterThan(result.count, 0)
    }

    /// The chart's right edge must be the newest reading; a downsample that
    /// dropped the tail would show the battery as it was minutes ago.
    func testNewestSampleSurvivesReduction() {
        let series = evenSeries(count: 1440)
        let result = WidgetHistoryDownsample.reduce(series)
        XCTAssertEqual(result.last?.t, series.last?.0)
    }

    func testOutputStaysChronological() {
        let result = WidgetHistoryDownsample.reduce(evenSeries(count: 1440))
        XCTAssertEqual(result.map(\.t), result.map(\.t).sorted())
    }

    /// Averaging per bucket, not sampling, so a dip inside a bucket still
    /// moves the line instead of being skipped entirely.
    func testBucketAveragingPreservesADip() {
        var series = evenSeries(count: 1000) { _ in 100 }
        for i in 400..<420 { series[i].1 = 0 }
        let result = WidgetHistoryDownsample.reduce(series)
        XCTAssertTrue(result.contains { $0.v < 100 })
    }

    /// Samples bunched in time must not be spread evenly across the axis.
    func testUnevenlySpacedSamplesKeepTheirTimestamps() {
        var series = evenSeries(count: 500)
        series += (0..<500).map {
            (start.addingTimeInterval(100_000 + Double($0)), Double($0))
        }
        let result = WidgetHistoryDownsample.reduce(series)
        XCTAssertEqual(result.first?.t, series.first?.0)
        XCTAssertEqual(result.last?.t, series.last?.0)
    }

    func testZeroLimitGivesNoPoints() {
        XCTAssertTrue(WidgetHistoryDownsample.reduce(evenSeries(count: 100), limit: 0).isEmpty)
    }

    /// All samples at one instant: no span to bucket by, so it must not divide
    /// by zero or return nothing.
    func testZeroSpanSeriesIsTruncatedNotCrashed() {
        let series = (0..<1000).map { (start, Double($0)) }
        let result = WidgetHistoryDownsample.reduce(series)
        XCTAssertEqual(result.count, WidgetHistoryDownsample.maxPoints)
    }
}
