import AppKit
import SwiftUI

/// Snaps the menu bar panel back to its content's height.
///
/// `MenuBarExtra(.window)` grows the panel when tall content appears but
/// never shrinks it again (observed on macOS 26): reopened on the short
/// "no connection" view, the panel keeps the tallest frame it has ever
/// shown and floats the content in the leftover space. This view sits in
/// the popover's background and re-fits the window whenever it lands in
/// one or the content case changes.
struct PopoverPanelSizer: NSViewRepresentable {
    /// Changes when the popover switches content case, so `updateNSView`
    /// fires and re-fits a panel that is already on screen.
    let stateKey: String

    /// The corrected window frame, or nil when the current one already fits.
    /// The top edge stays anchored — AppKit measures `origin.y` from the
    /// bottom of the screen, so the origin absorbs the height delta and the
    /// panel keeps hanging from the menu bar. Sub-point deltas are ignored,
    /// or every layout pass would jiggle the window.
    nonisolated static func fittedFrame(for frame: NSRect,
                                        fittingHeight: CGFloat) -> NSRect? {
        guard fittingHeight > 0 else { return nil }
        let delta = fittingHeight - frame.height
        guard abs(delta) > 1 else { return nil }
        var fitted = frame
        fitted.origin.y -= delta
        fitted.size.height = fittingHeight
        return fitted
    }

    func makeNSView(context: Context) -> TrackerView { TrackerView() }

    func updateNSView(_ view: TrackerView, context: Context) {
        view.refit()
    }

    final class TrackerView: NSView {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            refit()
        }

        func refit() {
            // After the in-flight layout pass — fittingSize is stale before it.
            DispatchQueue.main.async { [weak self] in
                guard let window = self?.window,
                      let content = window.contentView,
                      let frame = PopoverPanelSizer.fittedFrame(
                          for: window.frame,
                          fittingHeight: content.fittingSize.height) else { return }
                window.setFrame(frame, display: true)
            }
        }
    }
}
