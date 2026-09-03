import XCTest
@testable import RouterMenu

/// Guards the byte-counter arithmetic behind the hotspot driver's speeds.
/// The kernel's per-interface counters are cumulative since boot, so speed is
/// a delta between two samples — and every edge of that subtraction is a way
/// to render a nonsense number in the menu bar.
final class InterfaceCountersTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_756_000_000)

    func testSpeedIsTheDeltaOverElapsedTime() {
        let first = InterfaceSample(rxBytes: 1_000, txBytes: 500, at: t0)
        let second = InterfaceSample(rxBytes: 61_000, txBytes: 30_500,
                                     at: t0.addingTimeInterval(60))
        let speed = InterfaceSample.speed(from: first, to: second)
        XCTAssertEqual(speed?.rx, 1_000, "60 000 bytes over 60 s")
        XCTAssertEqual(speed?.tx, 500)
    }

    func testTheFirstSampleHasNoSpeedYet() {
        XCTAssertNil(InterfaceSample.speed(from: nil,
                                           to: InterfaceSample(rxBytes: 10, txBytes: 10, at: t0)),
                     "one sample cannot make a rate")
    }

    /// Reboots, interface re-creation and the kernel's 32-bit wrap all show up
    /// the same way: the new total is LOWER than the old one. Reporting the
    /// negative delta would render a huge bogus speed.
    func testACounterResetReportsZeroRatherThanANegativeSpeed() {
        let before = InterfaceSample(rxBytes: 900_000, txBytes: 900_000, at: t0)
        let after = InterfaceSample(rxBytes: 1_000, txBytes: 500,
                                    at: t0.addingTimeInterval(30))
        let speed = InterfaceSample.speed(from: before, to: after)
        XCTAssertEqual(speed?.rx, 0)
        XCTAssertEqual(speed?.tx, 0)
    }

    /// Two samples from the same refresh tick would divide by zero.
    func testSamplesWithNoElapsedTimeAreIgnored() {
        let a = InterfaceSample(rxBytes: 1_000, txBytes: 500, at: t0)
        let b = InterfaceSample(rxBytes: 2_000, txBytes: 900, at: t0)
        XCTAssertNil(InterfaceSample.speed(from: a, to: b))
    }

    func testClockSkewBackwardsIsIgnored() {
        let a = InterfaceSample(rxBytes: 1_000, txBytes: 500, at: t0)
        let b = InterfaceSample(rxBytes: 2_000, txBytes: 900,
                                at: t0.addingTimeInterval(-10))
        XCTAssertNil(InterfaceSample.speed(from: a, to: b),
                     "a backwards clock must not produce a negative rate")
    }
}
