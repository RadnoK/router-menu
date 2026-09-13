import XCTest
@testable import RouterMenu

final class WidgetAgeTextTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_756_000_000)
    private let en = Locale(identifier: "en_US")

    private func text(ageSeconds: TimeInterval) -> String {
        WidgetAgeText.string(capturedAt: now.addingTimeInterval(-ageSeconds),
                             now: now, locale: en)
    }

    /// The bug this type exists for: SwiftUI's `.relative` style measured
    /// against the system clock, rendering a 5-hour-old reading as "1 yr".
    func testHoursOldReadsAsHoursNotYears() {
        let result = text(ageSeconds: 5 * 3600)
        XCTAssertTrue(result.contains("hour"), "expected hours, got \(result)")
        XCTAssertFalse(result.contains("yr"))
        XCTAssertFalse(result.contains("year"))
    }

    func testMinutesOldReadsAsMinutes() {
        XCTAssertTrue(text(ageSeconds: 9 * 60).contains("minute"))
    }

    func testDaysOldReadsAsDays() {
        XCTAssertTrue(text(ageSeconds: 3 * 86400).contains("day"))
    }

    /// A snapshot stamped ahead of the clock must not render as "in 2 hours"
    /// on a widget that is showing a reading already taken.
    func testFutureCaptureIsNotDescribedAsUpcoming() {
        let result = WidgetAgeText.string(capturedAt: now.addingTimeInterval(2 * 3600),
                                          now: now, locale: en)
        XCTAssertFalse(result.lowercased().hasPrefix("in "), "got \(result)")
        XCTAssertFalse(result.contains("0 second"), "got \(result)")
    }
}
