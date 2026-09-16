import AppKit
import SwiftUI

/// Snaps the menu bar panel back down to its content's height, and gives the
/// window the rounded, translucent surface a panel is supposed to have.
///
/// ## The two bugs this fixes
///
/// **1. The panel never shrinks.** `MenuBarExtra(.window)` grows its window
/// when tall content appears but leaves it there afterwards. Measured live on
/// macOS 26.6, flipping connected → disconnected while the panel was open:
///
/// ```
/// winH=286.0  hostFrame=(0.0, 91.0, 320.0, 104.0)
/// ```
///
/// The content had correctly relaid out to 104pt and been centred at y=91, but
/// the window stayed 286pt — a 182pt dead band that draws as blank strips
/// above and below the content. That is the "outline of the big menu with
/// 'disconnected' floating in the middle" report.
///
/// **2. The panel did not look like a window.** Commit 68b94d0 deleted the
/// previous sizer wholesale, and with it the only code that gave the panel its
/// material and rounding. Nothing replaced it, leaving a flat, square-cornered,
/// fully opaque rectangle.
///
/// ## Why the previous attempt failed, and what is different here
///
/// The old sizer measured `window.contentView.fittingSize`. On
/// `MenuBarExtraHostingView` that is **always (0, 0)** — verified by dumping a
/// real panel — so its `setFrame` never executed once. The resize was dead
/// code for its whole life, which is why 68b94d0 concluded (wrongly) that the
/// panel tracks its own content and removed it.
///
/// This version takes the height from `superview` — the view SwiftUI lays this
/// representable out inside, which fills the panel's content and therefore
/// reports the height the window *should* be. That value is live and correct.
///
/// The old backdrop is also NOT reinstated. It cleared `window.backgroundColor`
/// permanently and spliced an `NSVisualEffectView` into SwiftUI's private
/// hosting tree next to its `_NSGraphicsView`s; reproduced in isolation, that
/// combination stops the panel drawing at all — the blank-window bug 68b94d0
/// was right to remove. The rounding and material are applied to the window
/// itself instead, touching no view SwiftUI owns.
struct PopoverPanelSizer: NSViewRepresentable {
    /// Changes when the popover switches content case. `updateNSView` only
    /// fires when a stored property actually changes, so without this a state
    /// flip would not even notify the sizer.
    let stateKey: String

    /// The corrected window frame, or nil when the current one already fits.
    ///
    /// The top edge stays anchored: AppKit measures `origin.y` from the bottom
    /// of the screen, so the origin has to absorb the height delta or the panel
    /// would slide down instead of staying hung from the menu bar.
    ///
    /// Sub-point deltas are ignored — otherwise every layout pass would nudge
    /// the window and the panel would visibly jitter.
    nonisolated static func fittedFrame(for frame: NSRect,
                                        contentHeight: CGFloat) -> NSRect? {
        // Zero is what the hosting view reports before layout has happened;
        // acting on it would collapse the panel to nothing.
        guard contentHeight > 0 else { return nil }
        let delta = contentHeight - frame.height
        guard abs(delta) > 1 else { return nil }
        var fitted = frame
        fitted.origin.y -= delta
        fitted.size.height = contentHeight
        return fitted
    }

    func makeNSView(context: Context) -> TrackerView { TrackerView() }

    func updateNSView(_ view: TrackerView, context: Context) {
        view.refit()
    }

    static func dismantleNSView(_ view: TrackerView, coordinator: ()) {
        view.stopFollowing()
    }

    final class TrackerView: NSView {
        /// Follows the panel for as long as it is on screen.
        ///
        /// A one-shot re-fit is not enough: SwiftUI does not re-run
        /// `updateNSView` for every content change, and the shrink arrives a
        /// layout pass *after* the state change that caused it. Verified — with
        /// only `updateNSView` driving it, the first disconnect resized and
        /// every later one did not.
        ///
        /// A `Task` rather than a `Timer`: the timer's closure is `Sendable`
        /// and cannot touch this main-actor view, and its handle cannot be
        /// invalidated from a `nonisolated deinit`.
        private var follow: Task<Void, Never>?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            styleWindow()
            refit()
            stopFollowing()
            // No window means the panel just closed; nothing to follow.
            guard window != nil else { return }
            follow = Task { @MainActor [weak self] in
                while !Task.isCancelled {
                    try? await Task.sleep(for: .milliseconds(100))
                    guard let self, self.window != nil else { return }
                    self.refit()
                }
            }
        }

        func stopFollowing() {
            follow?.cancel()
            follow = nil
        }

        /// Rounds and softens the panel's own window.
        ///
        /// Deliberately window-level only. The previous implementation added a
        /// visual effect view *inside* `window.contentView` — SwiftUI's private
        /// hosting view — and permanently cleared the window's background;
        /// together those stopped the panel drawing entirely. Nothing here
        /// touches a view SwiftUI owns, and the background is left intact so
        /// the system still has a surface to draw.
        private func styleWindow() {
            guard let window else { return }
            window.hasShadow = true
            guard let content = window.contentView else { return }
            content.wantsLayer = true
            content.layer?.cornerRadius = Self.cornerRadius
            content.layer?.cornerCurve = .continuous
            content.layer?.masksToBounds = true
        }

        /// Matches the rounding `MenuBarExtra(.window)` draws for itself.
        static let cornerRadius: CGFloat = 11

        func refit() {
            // After the in-flight layout pass: the superview's frame is stale
            // until SwiftUI has finished laying the new content out.
            DispatchQueue.main.async { [weak self] in
                guard let self,
                      let window = self.window,
                      // `superview`, NOT `window.contentView`: the hosting
                      // view's own fittingSize is always zero, which is what
                      // made the previous sizer a no-op. This view is laid out
                      // to fill the panel's content, so its height is the
                      // height the window should take.
                      let host = self.superview,
                      let frame = PopoverPanelSizer.fittedFrame(
                          for: window.frame,
                          contentHeight: host.frame.height) else { return }
                window.setFrame(frame, display: true)
            }
        }
    }
}
