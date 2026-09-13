import Foundation

/// Chooses the X-axis ticks for the widget's history chart.
///
/// `.automatic` puts a tick on the data's trailing edge, and Charts centres
/// each label on its tick — so at widget width the last one is drawn half
/// outside the plot and reads as a stray digit ("0" instead of "03:00").
/// Picking the positions here keeps every label whole, and makes the rule
/// testable rather than a layout detail nobody can assert on.
enum WidgetChartTicks {
    /// Fraction of the span kept clear at each end, wide enough for a label.
    static let edgeInset = 0.12

    static func dates(from points: [WidgetSnapshot.Point],
                      count: Int = 3,
                      calendar: Calendar = .current) -> [Date] {
        guard count > 0, let first = points.first?.t, let last = points.last?.t else { return [] }
        let span = last.timeIntervalSince(first)
        guard span > 0 else { return [] }

        // Ticks are snapped to whole hours. Evenly dividing the span put them
        // at arbitrary minutes ("06:38", "15:41"), which reads as noise on a
        // 24 h chart and makes the labels wider than the space allows.
        let inset = span * edgeInset
        let windowStart = first.addingTimeInterval(inset)
        let windowEnd = last.addingTimeInterval(-inset)
        guard windowEnd > windowStart else { return [] }

        let step = max(1, Int((windowEnd.timeIntervalSince(windowStart)
                               / Double(max(count - 1, 1))) / 3600))
        var result: [Date] = []
        var candidate = nextHour(after: windowStart, calendar: calendar)
        while candidate <= windowEnd, result.count < count {
            result.append(candidate)
            guard let advanced = calendar.date(byAdding: .hour, value: step, to: candidate)
            else { break }
            candidate = advanced
        }
        return result
    }

    private static func nextHour(after date: Date, calendar: Calendar) -> Date {
        let components = calendar.dateComponents([.year, .month, .day, .hour], from: date)
        guard let truncated = calendar.date(from: components) else { return date }
        return truncated < date
            ? calendar.date(byAdding: .hour, value: 1, to: truncated) ?? date
            : truncated
    }
}
