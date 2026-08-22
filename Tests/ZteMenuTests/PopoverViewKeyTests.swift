import XCTest
@testable import ZteMenu

@MainActor
final class PopoverViewKeyTests: XCTestCase {
    func testSignalQualityMapsToDistinctKeys() {
        let qualities: [SignalQuality] = [.noSignal, .veryWeak, .weak, .medium, .good, .veryGood]
        let keys = qualities.map { PopoverView.key(for: $0) }
        XCTAssertEqual(Set(keys).count, qualities.count, "signal keys must be distinct")
    }

    func testErrorKindMapsToDistinctKeys() {
        XCTAssertNotEqual(PopoverView.key(for: .loginFailed), PopoverView.key(for: .unreachable))
    }
}
