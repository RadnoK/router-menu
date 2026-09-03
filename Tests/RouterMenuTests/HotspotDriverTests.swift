import XCTest
@testable import RouterMenu

/// The hotspot driver reads the Mac's own interface instead of talking to a
/// device, so these tests hand it canned interface readings.
final class HotspotDriverTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_756_000_000)

    /// A stand-in for the live `getifaddrs` reader. `read()` and `now()` belong
    /// to the SAME fetch, so the cursor advances on `now()` — the driver's last
    /// call for that pass. Advancing on `read()` would hand the second sample
    /// the second reading but the third clock, making elapsed time zero.
    private struct StubReader: InterfaceReading {
        let readings: [InterfaceReading_Result?]
        let clock: [Date]
        let cursor = Cursor()
        final class Cursor: @unchecked Sendable { var n = 0 }

        func read() -> InterfaceReading_Result? {
            readings[min(cursor.n, readings.count - 1)]
        }

        func now() -> Date {
            defer { cursor.n += 1 }
            return clock[min(cursor.n, clock.count - 1)]
        }
    }

    private func reading(rx: Int, tx: Int, ssid: String? = "iPhone",
                         medium: HotspotMedium = .wifi) -> InterfaceReading_Result {
        InterfaceReading_Result(rxBytes: rx, txBytes: tx, ssid: ssid, medium: medium)
    }

    func testFirstFetchReportsTotalsButNoSpeedYet() async throws {
        let reader = StubReader(readings: [reading(rx: 5_000, tx: 2_000)], clock: [t0])
        let driver = HotspotDriver(reader: reader)
        let data = try await driver.fetch()

        XCTAssertEqual(data.totalRx, 5_000)
        XCTAssertEqual(data.totalTx, 2_000)
        XCTAssertNil(data.rxSpeed, "a rate needs two samples")
        XCTAssertNil(data.txSpeed)
        XCTAssertTrue(data.isOnline)
    }

    func testSecondFetchDerivesSpeedFromTheDelta() async throws {
        let reader = StubReader(
            readings: [reading(rx: 5_000, tx: 2_000), reading(rx: 65_000, tx: 8_000)],
            clock: [t0, t0.addingTimeInterval(60)])
        let driver = HotspotDriver(reader: reader)
        _ = try await driver.fetch()
        let data = try await driver.fetch()

        XCTAssertEqual(data.rxSpeed, 1_000, "60 000 bytes over 60 s")
        XCTAssertEqual(data.txSpeed, 100)
        XCTAssertEqual(data.totalRx, 65_000)
    }

    /// The phone's own battery and radio are unreachable from the Mac. The
    /// driver must leave them nil rather than invent a plausible-looking zero,
    /// which the popover would render as a real reading.
    func testPhoneSideMetricsStayUnknown() async throws {
        let reader = StubReader(readings: [reading(rx: 1, tx: 1)], clock: [t0])
        let data = try await HotspotDriver(reader: reader).fetch()

        XCTAssertNil(data.batteryPercent, "the iPhone's battery is not exposed to macOS")
        XCTAssertNil(data.rsrp)
        XCTAssertNil(data.sinr)
        XCTAssertNil(data.sessionRx)
        XCTAssertNil(data.monthlyRx)
        XCTAssertEqual(data.signalBars, 0)
    }

    func testTheLinkMediumBecomesTheNetworkLabel() async throws {
        for (medium, expected) in [(HotspotMedium.wifi, "Wi-Fi"),
                                   (.usb, "USB"),
                                   (.bluetooth, "Bluetooth")] {
            let reader = StubReader(readings: [reading(rx: 1, tx: 1, medium: medium)],
                                    clock: [t0])
            let data = try await HotspotDriver(reader: reader).fetch()
            XCTAssertEqual(data.networkType, expected)
        }
    }

    func testTheHotspotNameBecomesTheProvider() async throws {
        let reader = StubReader(readings: [reading(rx: 1, tx: 1, ssid: "iPhone (Konrad)")],
                                clock: [t0])
        let data = try await HotspotDriver(reader: reader).fetch()
        XCTAssertEqual(data.provider, "iPhone (Konrad)")
    }

    /// No reading means the tether is gone — the store treats a throw as
    /// "device not reachable", which is exactly right here.
    func testAVanishedInterfaceThrows() async {
        let reader = StubReader(readings: [nil], clock: [t0])
        let driver = HotspotDriver(reader: reader)
        do {
            _ = try await driver.fetch()
            XCTFail("expected a throw when the interface is gone")
        } catch {}
    }

    func testProbeFollowsTheInterfaceBeingPresent() async {
        let present = StubReader(readings: [reading(rx: 1, tx: 1)], clock: [t0])
        let absent = StubReader(readings: [nil], clock: [t0])
        let yes = await HotspotDriver(reader: present).probe()
        let no = await HotspotDriver(reader: absent).probe()
        XCTAssertTrue(yes)
        XCTAssertFalse(no)
    }
}
