import XCTest
@testable import ZteMenu

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

    func testUptime() {
        XCTAssertEqual(ByteFormat.uptime(7100), "1h 58m")
        XCTAssertEqual(ByteFormat.uptime(127070), "1d 11h")
        XCTAssertEqual(ByteFormat.uptime(45), "0h 0m")
    }
}
