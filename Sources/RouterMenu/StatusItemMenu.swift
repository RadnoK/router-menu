import AppKit

/// The right-click menu on the menu bar icon.
///
/// `MenuBarExtra` owns the primary click — it opens the popover — and offers
/// no hook for the secondary one, so the menu is built here and attached to
/// the status item directly. Quit lives in the popover's footer too; the point
/// of repeating it is that a right click is where people look for it, and the
/// popover has to be opened to reach the footer at all.
enum StatusItemMenu {
    @MainActor
    static func make(l10n: L10n) -> NSMenu {
        let menu = NSMenu()
        let quit = NSMenuItem(title: l10n(.popoverQuit),
                              action: #selector(NSApplication.terminate(_:)),
                              keyEquivalent: "q")
        // No target: the action travels the responder chain up to NSApp, which
        // is what implements terminate(_:).
        quit.target = nil
        menu.addItem(quit)
        return menu
    }
}

/// Watches one status-bar button for secondary clicks.
///
/// A local event monitor rather than an `NSStatusItem` menu: assigning a menu
/// to the button makes AppKit pop it on the primary click too, which takes the
/// popover away. The monitor sees the right click first, swallows it, and
/// leaves every other event to travel on untouched.
@MainActor
final class RightClickMonitor {
    /// The monitor handle is opaque and non-Sendable, so it lives in a box a
    /// nonisolated `deinit` is allowed to reach.
    private final class Handle: @unchecked Sendable {
        var token: Any?
        deinit { if let token { NSEvent.removeMonitor(token) } }
    }
    private let handle = Handle()

    init(button: NSStatusBarButton, onRightClick: @escaping () -> Void) {
        handle.token = NSEvent.addLocalMonitorForEvents(matching: [.rightMouseDown]) { [weak button] event in
            // Hit-test the button itself rather than comparing windows: the
            // status item lives in a system-owned window whose identity does
            // not match, and a window-level guard would either never fire or
            // swallow clicks meant for other status items.
            guard let button, let window = button.window,
                  event.window === window else { return event }
            let local = button.convert(event.locationInWindow, from: nil)
            guard button.bounds.contains(local) else { return event }
            onRightClick()
            return nil   // swallowed: AppKit must not also handle it
        }
    }
}
