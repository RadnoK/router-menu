import Foundation

/// The App Group both processes share. Registered under the Apprife team, so
/// it must match the `com.apple.security.application-groups` entitlement in
/// *both* the app and the widget or the container URL comes back nil.
public enum WidgetSharing {
    public static let appGroupID = "group.io.8lines.router-menu"
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
}
