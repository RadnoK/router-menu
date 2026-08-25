import XCTest
@testable import RouterMenu

final class ByteFormatTests: XCTestCase {
    func testGB() {
        XCTAssertEqual(ByteFormat.gb(1_073_741_824), "1.00 GB")
        XCTAssertEqual(ByteFormat.gb(20_248_857_403), "18.86 GB")
        XCTAssertEqual(ByteFormat.gb(0), "0.00 GB")
    }

    func testSpeed() {
        XCTAssertEqual(ByteFormat.speed(6149), "6.0 KB/s")
        XCTAssertEqual(ByteFormat.speed(1_500_000), "1.4 MB/s")
        XCTAssertEqual(ByteFormat.speed(500), "500 B/s")
    }

    func testSpeedGigabytesTier() {
        // Router-class throughput must never render as thousands of MB/s.
        XCTAssertEqual(ByteFormat.speed(2_147_483_648), "2.0 GB/s")
    }

    func testSpeedFromDouble() {
        // Chart axes hand over Double series values.
        XCTAssertEqual(ByteFormat.speed(750.0), "750 B/s")
        XCTAssertEqual(ByteFormat.speed(1536.0), "1.5 KB/s")
        XCTAssertEqual(ByteFormat.speed(5_242_880.0), "5.0 MB/s")
        XCTAssertEqual(ByteFormat.speed(2_147_483_648.0), "2.0 GB/s")
    }

    func testBytesScalesUnit() {
        XCTAssertEqual(ByteFormat.bytes(500), "500 B")
        XCTAssertEqual(ByteFormat.bytes(2048), "2.0 KB")
        XCTAssertEqual(ByteFormat.bytes(5_242_880), "5.0 MB")
        XCTAssertEqual(ByteFormat.bytes(2_684_354_560), "2.50 GB")
    }

    func testUptime() {
        XCTAssertEqual(ByteFormat.uptime(7100), "1h 58m")
        XCTAssertEqual(ByteFormat.uptime(127070), "1d 11h")
        XCTAssertEqual(ByteFormat.uptime(45), "0h 0m")
    }
}
