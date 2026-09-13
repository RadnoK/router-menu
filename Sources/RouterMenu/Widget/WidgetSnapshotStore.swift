import Foundation

/// The App Group both processes share. Must match the
/// `com.apple.security.application-groups` entitlement in *both* the app and
/// the widget, or the sandbox never grants the widget access.
public enum WidgetSharing {
    /// Prefixed with the Team ID, which is what makes the sandbox honour this
    /// on macOS WITHOUT a provisioning profile: for a Developer ID app the
    /// group is verified against the signing team, and a bare `group.*`
    /// identifier has nothing to verify against, so the entitlement is
    /// silently ignored and the widget reads an empty container while the
    /// (unsandboxed) app writes happily to the same path. Symptom: the widget
    /// shows "No modem data" while the menu bar is live.
    ///
    /// The unprefixed form is the iOS/App Store convention, where a
    /// provisioning profile supplies the proof instead. Every Developer ID app
    /// that ships a group uses the prefixed form.
    ///
    /// Changing this ORPHANS the previous container — see `legacyAppGroupIDs`.
    public static let appGroupID = "7S3F9767BM.io.8lines.router-menu"

    /// Containers from earlier builds, cleaned up on launch. 0.7.0-beta.1
    /// shipped the unprefixed id, which left a stale directory behind holding
    /// a snapshot nothing reads.
    public static let legacyAppGroupIDs = ["group.io.8lines.router-menu"]
    public static let snapshotFilename = "widget-snapshot.json"
    /// WidgetKit addresses timelines by kind string; it must match the
    /// `@main` widget's `kind` exactly.
    public static let widgetKind = "RouterMenuWidget"
}

/// Reads and writes the snapshot in the shared container.
///
/// Both sides use this type, which is why it is plain `Foundation` and has no
/// opinion about WidgetKit: the app writes, the extension reads, and neither
/// can hold a lock on the other. A half-written file is the real hazard here,
/// so writes are atomic and a failed read is simply "no data" rather than an
/// error the widget would have to render.
public struct WidgetSnapshotStore {
    private let fileURL: URL?

    /// - Parameter containerURL: injected in tests. In the app and the widget
    ///   this resolves through the App Group, which the app must tolerate
    ///   failing: without the entitlement there is no widget to feed, and the
    ///   app itself has to keep running normally. Every operation degrades to
    ///   a no-op rather than an error the caller has to handle.
    ///
    ///   Note `containerURL(forSecurityApplicationGroupIdentifier:)` returns a
    ///   *path*, not a guarantee: in an unsandboxed process it hands back a URL
    ///   under ~/Library/Group Containers even when no such directory exists,
    ///   and macOS only creates it for a process actually entitled to the
    ///   group. Availability is therefore decided by whether the directory is
    ///   really there — checking the URL alone silently dropped every write.
    public init(containerURL: URL? = FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: WidgetSharing.appGroupID)) {
        guard let containerURL,
              FileManager.default.fileExists(atPath: containerURL.path) else {
            self.fileURL = nil
            return
        }
        self.fileURL = containerURL.appendingPathComponent(WidgetSharing.snapshotFilename)
    }

    public var isAvailable: Bool { fileURL != nil }

    public func write(_ snapshot: WidgetSnapshot) {
        guard let fileURL else { return }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(snapshot) else { return }
        // .atomic so the widget never reads a torn file mid-write.
        try? data.write(to: fileURL, options: .atomic)
    }

    public func read() -> WidgetSnapshot? {
        guard let fileURL, let data = try? Data(contentsOf: fileURL) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(WidgetSnapshot.self, from: data)
    }

    public func clear() {
        guard let fileURL else { return }
        try? FileManager.default.removeItem(at: fileURL)
    }

    /// Deletes snapshots left in containers this app no longer uses.
    ///
    /// Only the snapshot file is removed, never the container directory:
    /// `containerURL(...)` reports a path for any group an unsandboxed process
    /// asks about, so deleting the directory outright risks removing something
    /// this app never owned.
    public static func removeLegacySnapshots(
        containerURL: (String) -> URL? = {
            FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: $0)
        }
    ) {
        for id in WidgetSharing.legacyAppGroupIDs {
            guard let container = containerURL(id) else { continue }
            let stale = container.appendingPathComponent(WidgetSharing.snapshotFilename)
            guard FileManager.default.fileExists(atPath: stale.path) else { continue }
            try? FileManager.default.removeItem(at: stale)
        }
    }
}
