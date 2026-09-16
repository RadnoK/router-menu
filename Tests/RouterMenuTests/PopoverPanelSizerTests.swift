import XCTest
import AppKit
@testable import RouterMenu

/// Guards the frame math that snaps the menu bar panel back to its content.
///
/// The bug this exists to prevent: `MenuBarExtra(.window)` grows its panel
/// when tall content appears but does NOT shrink it again. Measured live on
/// macOS 26.6 — after a connected → disconnected flip the window stayed at
/// 286pt while the laid-out content had already shrunk to 104pt and been
/// offset to y=91, leaving a 182pt dead band drawn as blank strips above and
/// below the content.
///
/// An earlier sizer tried to fix this with `contentView.fittingSize`, which
/// is **always (0, 0)** on `MenuBarExtraHostingView` — so its `setFrame` never
/// ran once and the mechanism was dead code. The height has to come from the
/// laid-out content view instead; that is what `fittedFrame` is fed.
final class PopoverPanelSizerTests: XCTestCase {
    private let tall = NSRect(x: 100, y: 100, width: 320, height: 286)

    func testShrinkKeepsTheTopEdgeAnchored() {
        let fitted = PopoverPanelSizer.fittedFrame(for: tall, contentHeight: 104)
        XCTAssertEqual(fitted, NSRect(x: 100, y: 282, width: 320, height: 104))
        // AppKit measures origin.y from the bottom of the screen, so the
        // origin must absorb the delta or the panel would slide down the
        // screen instead of staying hung from the menu bar.
        XCTAssertEqual(fitted?.maxY, tall.maxY, "the panel hangs from the menu bar")
    }

    func testGrowthKeepsTheTopEdgeAnchored() {
        let fitted = PopoverPanelSizer.fittedFrame(for: tall, contentHeight: 400)
        XCTAssertEqual(fitted, NSRect(x: 100, y: -14, width: 320, height: 400))
        XCTAssertEqual(fitted?.maxY, tall.maxY)
    }

    func testNearMissesDoNotResize() {
        // Sub-point deltas would make every layout pass jiggle the window.
        XCTAssertNil(PopoverPanelSizer.fittedFrame(for: tall, contentHeight: 286.5))
        XCTAssertNil(PopoverPanelSizer.fittedFrame(for: tall, contentHeight: 286))
    }

    func testDegenerateContentHeightIsIgnored() {
        // A zero height is what the hosting view reports before layout; acting
        // on it would collapse the panel to nothing.
        XCTAssertNil(PopoverPanelSizer.fittedFrame(for: tall, contentHeight: 0))
        XCTAssertNil(PopoverPanelSizer.fittedFrame(for: tall, contentHeight: -50))
    }
}
