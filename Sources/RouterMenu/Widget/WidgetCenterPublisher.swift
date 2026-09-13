import Foundation
import WidgetKit

/// Writes the snapshot to the shared container, then asks WidgetKit to redraw.
///
/// The reload is a *request*: WidgetKit budgets refreshes (roughly 40–70 a
/// day), so a reload on every 60 s tick would be throttled and the later,
/// more interesting readings dropped. Writing unconditionally but reloading
/// only on a meaningful change keeps the budget for changes worth showing.
@MainActor
final class WidgetCenterPublisher: WidgetPublishing {
    private let store: WidgetSnapshotStore
    private var lastPublished: WidgetSnapshot?

    init(store: WidgetSnapshotStore = WidgetSnapshotStore()) {
        self.store = store
    }

    func publish(_ snapshot: WidgetSnapshot) {
        // No App Group (ad-hoc local build): nothing can read the file and no
        // widget is installed, so skip the work entirely.
        guard store.isAvailable else { return }
        store.write(snapshot)
        if Self.isWorthReloading(previous: lastPublished, next: snapshot) {
            lastPublished = snapshot
            WidgetCenter.shared.reloadTimelines(ofKind: WidgetSharing.widgetKind)
        }
    }

    func clear() {
        guard store.isAvailable else { return }
        store.clear()
        lastPublished = nil
        WidgetCenter.shared.reloadTimelines(ofKind: WidgetSharing.widgetKind)
    }

    /// Everything the widget actually renders, except the timestamp and the
    /// speeds. Transfer rates change on every single tick, so including them
    /// would make every reading "a change" and exhaust the refresh budget by
    /// mid-morning — the widget shows them, but they are not worth spending a
    /// reload on by themselves.
    nonisolated static func isWorthReloading(previous: WidgetSnapshot?, next: WidgetSnapshot) -> Bool {
        guard let previous else { return true }
        return previous.batteryPercent != next.batteryPercent
            || previous.isCharging != next.isCharging
            || previous.signalBars != next.signalBars
            || previous.networkLabel != next.networkLabel
            || previous.isOnline != next.isOnline
            || previous.deviceName != next.deviceName
    }
}
