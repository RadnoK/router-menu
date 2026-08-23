import Foundation
import ServiceManagement

/// Registration with the system's login items.
///
/// A protocol rather than a direct `SMAppService` call so tests can exercise
/// the toggle without registering the test runner to launch at login.
@MainActor
protocol LoginItemManaging {
    /// Read from the system every time, never cached: the user can remove the
    /// app in System Settings › General › Login Items, and a stored copy of
    /// this flag would then be a lie.
    var isEnabled: Bool { get }
    func setEnabled(_ enabled: Bool) throws
}

/// Registers the app itself — not a helper — with `SMAppService`.
///
/// Deliberately absent from `AppSettings`: the system owns this state, so
/// persisting our own copy could only ever drift out of sync with it.
@MainActor
struct LoginItem: LoginItemManaging {
    private let service = SMAppService.mainApp

    var isEnabled: Bool { service.status == .enabled }

    func setEnabled(_ enabled: Bool) throws {
        if enabled {
            try service.register()
        } else {
            try service.unregister()
        }
    }
}

/// Backs the "Launch at login" toggle: mirrors the system's registration and
/// keeps the switch honest when the system refuses a change.
///
/// Registration can fail — an app running from a location the system will not
/// launch (a build directory, a quarantined copy) is rejected. Without this
/// type the toggle would flip on screen while the system stayed unregistered,
/// which is the one failure the user cannot see for themselves.
@MainActor
@Observable
public final class LoginItemController {
    private(set) var isEnabled: Bool
    /// Set when the last change was rejected, so the UI can explain why the
    /// toggle snapped back. Cleared by the next successful change.
    private(set) var lastError: String?
    private let item: any LoginItemManaging

    /// The app's entry point, registering the real `SMAppService`.
    public convenience init() {
        self.init(item: LoginItem())
    }

    init(item: any LoginItemManaging) {
        self.item = item
        isEnabled = item.isEnabled
    }

    /// Re-reads the system state — the settings window calls this on appear,
    /// because the user may have changed it in System Settings meanwhile.
    func refresh() {
        isEnabled = item.isEnabled
    }

    func setEnabled(_ enabled: Bool) {
        do {
            try item.setEnabled(enabled)
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
        // Either way, show what the system actually holds rather than what was
        // asked for.
        refresh()
    }
}
