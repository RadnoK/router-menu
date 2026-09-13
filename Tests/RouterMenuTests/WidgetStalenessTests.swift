import XCTest
@testable import RouterMenu

final class WidgetStalenessTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    private func freshness(ageSeconds: TimeInterval) -> WidgetFreshness {
        WidgetFreshness.of(now.addingTimeInterval(-ageSeconds), now: now)
    }

    func testJustCapturedIsFresh() {
        XCTAssertEqual(freshness(ageSeconds: 0), .fresh)
    }

    func testWithinAFewRefreshCyclesIsFresh() {
        XCTAssertEqual(freshness(ageSeconds: 4 * 60), .fresh)
    }

    func testBoundaryBetweenFreshAndAging() {
        XCTAssertEqual(freshness(ageSeconds: WidgetFreshness.agingAfter - 1), .fresh)
        XCTAssertEqual(freshness(ageSeconds: WidgetFreshness.agingAfter), .aging)
    }

    func testBoundaryBetweenAgingAndStale() {
        XCTAssertEqual(freshness(ageSeconds: WidgetFreshness.staleAfter - 1), .aging)
        XCTAssertEqual(freshness(ageSeconds: WidgetFreshness.staleAfter), .stale)
    }

    func testHoursOldIsStale() {
        XCTAssertEqual(freshness(ageSeconds: 6 * 3600), .stale)
    }

    /// A snapshot slightly ahead of the clock is ordinary scheduling jitter.
    func testSlightlyFutureCaptureIsStillFresh() {
        XCTAssertEqual(freshness(ageSeconds: -30), .fresh)
    }

    /// A wildly future timestamp means the clock moved, not that the modem
    /// reported ahead of time — trusting it would freeze a wrong reading.
    func testFarFutureCaptureIsStale() {
        XCTAssertEqual(freshness(ageSeconds: -2 * 3600), .stale)
    }
}
