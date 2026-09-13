import Foundation

/// How old the reading is, in words.
///
/// Not `Text(date, style: .relative)`: that style measures against the system
/// clock at draw time, so it ignores the timeline entry's own date and — when
/// the snapshot's timestamp and the clock disagree — renders nonsense like
/// "1 yr" for a five-hour-old reading. Formatting it ourselves keeps the age
/// tied to the moment the widget is actually rendering for.
enum WidgetAgeText {
    static func string(capturedAt: Date, now: Date,
                       locale: Locale = .current) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = locale
        formatter.unitsStyle = .full
        // A capture in the future is a clock adjustment, not a prediction, so
        // it must not render as "in 3 hours" on a reading already taken.
        // Clamping alone gives "in 0 seconds"; the age is reported as zero
        // explicitly instead, which is what the widget means by it.
        // Every RelativeDateTimeFormatter path for a zero or negative age
        // renders "in 0 seconds", which reads as a prediction on a widget
        // showing a reading already taken. A localized phrase says it plainly.
        // In practice the widget only draws this line once a reading is
        // aging, so this is the guard for a clock that jumped backwards.
        guard capturedAt < now else { return WidgetCopy.justNow }
        return formatter.localizedString(for: capturedAt, relativeTo: now)
    }
}
