import XCTest
import CoreLocation
@testable import RouterMenu

final class LocationPermissionTests: XCTestCase {
    func testMapsStatuses() {
        XCTAssertEqual(LocationAuth.from(.notDetermined), .notDetermined)
        XCTAssertEqual(LocationAuth.from(.denied), .denied)
        XCTAssertEqual(LocationAuth.from(.restricted), .denied)
        XCTAssertEqual(LocationAuth.from(.authorized), .authorized)
        XCTAssertEqual(LocationAuth.from(.authorizedAlways), .authorized)
    }
}
