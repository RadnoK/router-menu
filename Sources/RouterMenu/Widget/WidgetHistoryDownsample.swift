import Foundation

/// Shrinks a 24 h series to something worth writing to the shared container.
///
/// At a 60 s refresh the history holds ~1440 points, rewritten on every tick.
/// The large widget's chart is a few hundred points wide at most, so shipping
/// all of them burns disk writes and decode time in an extension that is
/// memory-limited and killed if it overruns.
public enum WidgetHistoryDownsample {
    /// Roughly one point per 10 minutes across 24 h, which is finer than the
    /// chart can resolve.
    public static let maxPoints = 144

    /// Buckets by time rather than by index: samples are not evenly spaced
    /// (the app sleeps, the modem drops off), so taking every Nth point would
    /// stretch gaps into straight lines that imply readings we never took.
    /// Each bucket reports its mean, so a dip is visible instead of aliased.
    public static func reduce(_ series: [(Date, Double)], limit: Int = maxPoints) -> [WidgetSnapshot.Point] {
        guard limit > 0 else { return [] }
        guard series.count > limit else {
            return series.map { WidgetSnapshot.Point(t: $0.0, v: $0.1) }
        }
        guard let first = series.first?.0, let last = series.last?.0 else { return [] }

        let span = last.timeIntervalSince(first)
        // A series with no time span (or a clock that went backwards) can't be
        // bucketed — keep the newest points and stop.
        guard span > 0 else {
            return series.suffix(limit).map { WidgetSnapshot.Point(t: $0.0, v: $0.1) }
        }

        let bucketSize = span / Double(limit)
        var buckets: [(start: Date, end: Date, sum: Double, count: Int)] = []
        var bucketIndex = 0

        for (t, v) in series {
            let index = min(Int(t.timeIntervalSince(first) / bucketSize), limit - 1)
            if index != bucketIndex || buckets.isEmpty {
                buckets.append((start: t, end: t, sum: v, count: 1))
                bucketIndex = index
            } else {
                buckets[buckets.count - 1].end = t
                buckets[buckets.count - 1].sum += v
                buckets[buckets.count - 1].count += 1
            }
        }

        // Inner buckets are stamped with the midpoint of the samples they
        // actually hold: stamping an edge slid a dense bucket's point away
        // from the data it summarises. The two outer buckets instead keep the
        // real first and last timestamps, because the chart's edges are read
        // as "when the history starts" and "the latest reading" — a midpoint
        // there would quietly crop both ends of the axis.
        return buckets.enumerated().map { index, b in
            let mean = b.sum / Double(b.count)
            if index == 0 { return WidgetSnapshot.Point(t: b.start, v: mean) }
            if index == buckets.count - 1 { return WidgetSnapshot.Point(t: b.end, v: mean) }
            let mid = b.start.addingTimeInterval(b.end.timeIntervalSince(b.start) / 2)
            return WidgetSnapshot.Point(t: mid, v: mean)
        }
    }
}
