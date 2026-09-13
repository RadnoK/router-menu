import WidgetKit
import SwiftUI
import RouterMenu

@main
struct RouterMenuWidgetBundle: WidgetBundle {
    var body: some Widget {
        RouterMenuWidget()
    }
}

struct RouterMenuWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WidgetSharing.widgetKind,
                            provider: RouterMenuTimelineProvider()) { entry in
            RouterMenuWidgetEntryView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName(WidgetCopy.displayName)
        .description(WidgetCopy.description)
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

struct RouterMenuEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot?
}

struct RouterMenuWidgetEntryView: View {
    @Environment(\.widgetFamily) private var family
    let entry: RouterMenuEntry

    var body: some View {
        WidgetContentView(snapshot: entry.snapshot,
                          freshness: entry.snapshot
                              .map { WidgetFreshness.of($0.capturedAt, now: entry.date) }
                              ?? .stale,
                          family: layoutFamily,
                          now: entry.date)
    }

    private var layoutFamily: WidgetLayoutFamily {
        switch family {
        case .systemSmall: return .small
        case .systemLarge, .systemExtraLarge: return .large
        default: return .medium
        }
    }
}

struct RouterMenuTimelineProvider: TimelineProvider {
    private let store = WidgetSnapshotStore()

    /// Drawn in the widget gallery and while the real entry loads, so it shows
    /// plausible values rather than an empty frame the user would read as broken.
    func placeholder(in context: Context) -> RouterMenuEntry {
        RouterMenuEntry(date: Date(), snapshot: WidgetSnapshotPreview.sample)
    }

    func getSnapshot(in context: Context, completion: @escaping (RouterMenuEntry) -> Void) {
        // The gallery has no App Group data to show, so it gets the sample.
        let snapshot = context.isPreview
            ? WidgetSnapshotPreview.sample
            : store.read()
        completion(RouterMenuEntry(date: Date(), snapshot: snapshot))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<RouterMenuEntry>) -> Void) {
        let now = Date()
        let snapshot = store.read()

        // Entries the widget can render WITHOUT being woken: the reading does
        // not change, but its age does, so pre-scheduling the moments it turns
        // aging and then stale means the "5 minutes ago" line appears on time
        // even if WidgetKit never reloads us. Without this, a quit app would
        // leave a months-old reading looking perfectly current.
        var entries = [RouterMenuEntry(date: now, snapshot: snapshot)]
        if let capturedAt = snapshot?.capturedAt {
            for boundary in [WidgetFreshness.agingAfter, WidgetFreshness.staleAfter] {
                let at = capturedAt.addingTimeInterval(boundary)
                if at > now { entries.append(RouterMenuEntry(date: at, snapshot: snapshot)) }
            }
        }

        // `.after` rather than `.atEnd`: the app pushes a reload whenever the
        // reading actually changes, so this is only the fallback that keeps a
        // widget updating when the app is running but nothing notable moved.
        completion(Timeline(entries: entries,
                            policy: .after(now.addingTimeInterval(15 * 60))))
    }
}
