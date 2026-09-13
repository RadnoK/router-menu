import Foundation

/// How much to trust what the snapshot says.
///
/// The widget's whole failure mode is confidently showing a number the modem
/// stopped reporting hours ago: WidgetKit wakes the extension on its own
/// schedule and the app may be quit, asleep, or off the network, yet the last
/// snapshot still sits on disk looking exactly like a fresh one.
public enum WidgetFreshness: Equatable {
    /// Within one refresh cycle of the app's own loop — render plainly.
    case fresh
    /// Late, but plausibly a missed tick. Render with a relative timestamp.
    case aging
    /// The app is not running or cannot reach the modem. Render dimmed, and
    /// never imply the reading is current.
    case stale

    /// `Config.refreshInterval` is 60 s, so a snapshot is only "fresh" for a
    /// couple of ticks. The thresholds are generous compared to that: the
    /// widget is redrawn by WidgetKit, not by us, so a 3-minute-old reading
    /// usually means "no timeline refresh yet", not "the app died".
    public static func of(_ capturedAt: Date, now: Date) -> WidgetFreshness {
        let age = now.timeIntervalSince(capturedAt)
        // A snapshot from the future is a clock change, not a fresh reading.
        // Treating it as fresh would pin the widget to a wrong value until the
        // clock caught up, so it is judged by magnitude instead.
        if age < -staleAfter { return .stale }
        if age < agingAfter { return .fresh }
        if age < staleAfter { return .aging }
        return .stale
    }

    public static let agingAfter: TimeInterval = 5 * 60
    public static let staleAfter: TimeInterval = 30 * 60
}
