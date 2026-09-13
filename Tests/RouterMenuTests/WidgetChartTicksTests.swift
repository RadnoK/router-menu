import XCTest
@testable import RouterMenu

final class WidgetChartTicksTests: XCTestCase {
    private var calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()
    private let start = Date(timeIntervalSince1970: 1_756_000_000)

    private func points(hours: Double) -> [WidgetSnapshot.Point] {
        [.init(t: start, v: 100),
         .init(t: start.addingTimeInterval(hours * 3600), v: 20)]
    }

    private func ticks(hours: Double, count: Int = 3) -> [Date] {
        WidgetChartTicks.dates(from: points(hours: hours), count: count, calendar: calendar)
    }

    func testEmptySeriesHasNoTicks() {
        XCTAssertTrue(WidgetChartTicks.dates(from: [], calendar: calendar).isEmpty)
    }

    func testSingleInstantSeriesHasNoTicks() {
        let same = [WidgetSnapshot.Point(t: start, v: 1), .init(t: start, v: 2)]
        XCTAssertTrue(WidgetChartTicks.dates(from: same, calendar: calendar).isEmpty)
    }

    func testNeverExceedsTheRequestedCount() {
        XCTAssertLessThanOrEqual(ticks(hours: 24).count, 3)
    }

    /// The bug this type exists for: a tick on the trailing edge had its
    /// centred label clipped in half, rendering "03:00" as a bare "0".
    func testTicksStayClearOfBothEdges() {
        let series = points(hours: 24)
        guard let first = series.first?.t, let last = series.last?.t else {
            return XCTFail("fixture")
        }
        let inset = last.timeIntervalSince(first) * WidgetChartTicks.edgeInset
        for tick in ticks(hours: 24) {
            XCTAssertGreaterThanOrEqual(tick, first.addingTimeInterval(inset))
            XCTAssertLessThanOrEqual(tick, last.addingTimeInterval(-inset))
        }
    }

    /// Evenly dividing the span produced labels like "06:38", which read as
    /// noise next to a clock.
    func testTicksLandOnWholeHours() {
        for tick in ticks(hours: 24) {
            let parts = calendar.dateComponents([.minute, .second], from: tick)
            XCTAssertEqual(parts.minute, 0, "tick \(tick) is not on the hour")
            XCTAssertEqual(parts.second, 0)
        }
    }

    func testTicksAreChronological() {
        let result = ticks(hours: 24)
        XCTAssertEqual(result, result.sorted())
    }

    /// A widget shown minutes after launch has almost no history; it must not
    /// crash or invent ticks outside the data.
    func testVeryShortSpanDoesNotProduceOutOfRangeTicks() {
        for tick in ticks(hours: 0.5) {
            XCTAssertGreaterThanOrEqual(tick, start)
            XCTAssertLessThanOrEqual(tick, start.addingTimeInterval(1800))
        }
    }

    func testZeroCountRequestGivesNoTicks() {
        XCTAssertTrue(ticks(hours: 24, count: 0).isEmpty)
    }

    func testSingleTickRequestIsHonoured() {
        XCTAssertLessThanOrEqual(ticks(hours: 24, count: 1).count, 1)
    }
}
