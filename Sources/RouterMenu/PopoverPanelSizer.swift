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
/// **2. The panel looked like a flat grey slab.** `MenuBarExtra(.window)`
/// ships no material of its own on macOS 26 — dumped from a live panel, its
/// content view holds only two flat `_NSGraphicsView`s, one an opaque grey
/// fill. Without a backdrop the panel reads as grey and dated next to every
/// other menu bar surface on the system.
///
/// ## Why the previous sizing attempt failed, and what is different here
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
/// ## Why the backdrop is back, after being removed twice as broken
///
/// An earlier backdrop here was removed on the grounds that clearing
/// `window.backgroundColor` and splicing an `NSVisualEffectView` into
/// SwiftUI's hosting tree "stops the panel drawing at all". The sibling
/// project deploybar chased the same blank panel through four releases and
/// reached the same wrong conclusion twice, before measuring it properly.
/// Two things were actually going on, and neither is the backdrop:
///
///   * **A missing `window.hasShadow = true`.** With the background cleared
///     and no shadow, the window has no layer forcing a background draw and
///     the panel comes up as an empty rectangle. Verified both ways on Release
///     builds: material with the shadow renders fully, the same build without
///     it renders nothing.
///   * **The SDK the app was built against.** Built against the macOS 15 SDK,
///     the app gets the older AppKit behaviour at runtime, and *there* a
///     cleared panel background does make `MenuBarExtra` draw nothing on
///     macOS 26. deploybar measured panel content as pixel variance across
///     builds of one commit — 39 = content, 3 = blank — and every SDK 27 build
///     rendered while the SDK 15.2 CI artifact was blank. The release workflow
///     asserts SDK 26+ for exactly this reason.
///
/// So the backdrop is added the way remote-mac does it: an
/// `NSVisualEffectView` *below* the existing views, with the window's
/// background cleared, none of their layers rewritten, and the shadow kept.
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

        /// Rounds the panel, gives it a shadow, and slots an
        /// `NSVisualEffectView` underneath so the desktop reads through it.
        ///
        /// The ordering is what makes this work: the backdrop goes *below* the
        /// views SwiftUI already put in the content view, and none of their
        /// layers are rewritten. An earlier attempt cleared the opaque grey
        /// fill's own layer instead, and that is what stopped the panel
        /// drawing.
        ///
        /// **`window.hasShadow` is load-bearing, not decoration.** Dropping it
        /// while `backgroundColor` is cleared leaves the window with no layer
        /// forcing a background draw, and the panel comes up as an empty
        /// rectangle. It must stay above the `contentView` guard — a merged
        /// `guard` that swallowed this line is what shipped a blank panel in
        /// deploybar 1.0.0-beta. See the note on the type.
        ///
        /// Idempotent: `viewDidMoveToWindow` fires again whenever the panel is
        /// rebuilt, and a second effect view would stack another wash of tint.
        private func styleWindow() {
            guard let window else { return }
            window.hasShadow = true
            guard let content = window.contentView else { return }
            window.isOpaque = false
            window.backgroundColor = .clear

            content.wantsLayer = true
            content.layer?.cornerRadius = Self.cornerRadius
            content.layer?.cornerCurve = .continuous
            content.layer?.masksToBounds = true

            guard !content.subviews.contains(where: { $0 is Backdrop }) else { return }
            let backdrop = Backdrop()
            // `.menu` is the thinnest of the popover materials, which is the
            // point: the panel should read as glass, not as frosted plastic.
            backdrop.material = .menu
            backdrop.blendingMode = .behindWindow
            // .active, not .followsWindowActiveState: the panel resigns key as
            // soon as the user clicks another app, and a backdrop that goes
            // solid grey on the way out is the bug this came to fix.
            backdrop.state = .active
            backdrop.autoresizingMask = [.width, .height]
            backdrop.frame = content.bounds
            // Clipped to the panel's own corners — clearing the window drops
            // the system's rounding, leaving the material square at the tips.
            backdrop.wantsLayer = true
            backdrop.layer?.cornerRadius = Self.cornerRadius
            backdrop.layer?.cornerCurve = .continuous
            backdrop.layer?.masksToBounds = true
            content.addSubview(backdrop, positioned: .below, relativeTo: nil)
        }

        /// A marker class, so the idempotence check cannot mistake some other
        /// effect view SwiftUI may park in the panel for ours.
        final class Backdrop: NSVisualEffectView {}

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
