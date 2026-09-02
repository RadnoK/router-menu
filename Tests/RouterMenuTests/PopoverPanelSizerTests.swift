import XCTest
@testable import RouterMenu

/// Guards the frame math that shrinks the menu bar panel back to its
/// content, and the state key that tells the sizer when to re-fit.
final class PopoverPanelSizerTests: XCTestCase {
    private let tall = NSRect(x: 100, y: 100, width: 334, height: 700)

    func testShrinkKeepsTheTopEdgeAnchored() {
        let fitted = PopoverPanelSizer.fittedFrame(for: tall, fittingHeight: 200)
        XCTAssertEqual(fitted, NSRect(x: 100, y: 600, width: 334, height: 200))
        XCTAssertEqual(fitted.map { $0.maxY }, tall.maxY, "the panel hangs from the menu bar")
    }

    func testGrowthKeepsTheTopEdgeAnchored() {
        let fitted = PopoverPanelSizer.fittedFrame(for: tall, fittingHeight: 900)
        XCTAssertEqual(fitted, NSRect(x: 100, y: -100, width: 334, height: 900))
    }

    func testNearMissesDoNotResize() {
        XCTAssertNil(PopoverPanelSizer.fittedFrame(for: tall, fittingHeight: 700.5),
                     "sub-point deltas would make every layout pass jiggle the window")
        XCTAssertNil(PopoverPanelSizer.fittedFrame(for: tall, fittingHeight: 700))
    }

    func testDegenerateFittingHeightIsIgnored() {
        XCTAssertNil(PopoverPanelSizer.fittedFrame(for: tall, fittingHeight: 0))
        XCTAssertNil(PopoverPanelSizer.fittedFrame(for: tall, fittingHeight: -50))
    }

    func testStateKeyDistinguishesEveryContentCase() {
        let keys = [PopoverView.stateKey(for: .hidden),
                    PopoverView.stateKey(for: .locationDenied),
                    PopoverView.stateKey(for: .error(.unreachable)),
                    PopoverView.stateKey(for: .connected(Self.data))]
        XCTAssertEqual(Set(keys).count, keys.count, "each case must trigger a re-fit")
    }

    func testStateKeyIgnoresThePayload() {
        XCTAssertEqual(PopoverView.stateKey(for: .connected(Self.data)),
                       PopoverView.stateKey(for: .connected(Self.otherData)),
                       "data ticks must not thrash the window while open")
    }

    /// The backdrop install runs on every `viewDidMoveToWindow`, which fires
    /// again each time the panel is rebuilt. Stacking effect views would
    /// darken the material one wash per reopen.
    @MainActor
    func testBackdropIsInstalledOncePerWindow() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 320, height: 400),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        let tracker = PopoverPanelSizer.TrackerView()
        window.contentView?.addSubview(tracker)

        func backdrops() -> Int {
            window.contentView?.subviews
                .filter { $0 is PopoverPanelSizer.TrackerView.Backdrop }.count ?? 0
        }
        XCTAssertEqual(backdrops(), 1, "moving into a window installs the material")

        tracker.removeFromSuperview()
        window.contentView?.addSubview(tracker)
        XCTAssertEqual(backdrops(), 1, "a rebuilt panel must not stack a second wash")
    }

    @MainActor
    func testBackdropClearsTheOpaqueWindowFill() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 320, height: 400),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.isOpaque = true
        window.backgroundColor = .windowBackgroundColor
        window.contentView?.addSubview(PopoverPanelSizer.TrackerView())

        XCTAssertFalse(window.isOpaque, "an opaque window would blur to flat grey")
        XCTAssertEqual(window.backgroundColor, NSColor.clear)
    }

    private static let data = makeData(signalBars: 4)
    private static let otherData = makeData(signalBars: 1)

    private static func makeData(signalBars: Int) -> ModemData {
        ModemData(batteryPercent: nil, isCharging: false, signalBars: signalBars,
                  networkType: "LTE", provider: nil, rsrp: nil, sinr: nil,
                  isOnline: true, rxSpeed: nil, txSpeed: nil, sessionRx: nil,
                  sessionTx: nil, totalRx: nil, totalTx: nil, monthlyRx: nil,
                  monthlyTx: nil, sessionUptime: nil, monthlyUptime: nil)
    }
}
