import XCTest
@testable import RouterMenu

@MainActor
final class LoginItemControllerTests: XCTestCase {
    func testReflectsTheSystemStateAtInit() {
        XCTAssertTrue(LoginItemController(item: FakeLoginItem(enabled: true)).isEnabled)
        XCTAssertFalse(LoginItemController(item: FakeLoginItem(enabled: false)).isEnabled)
    }

    func testEnablingRegistersWithTheSystem() {
        let fake = FakeLoginItem(enabled: false)
        let controller = LoginItemController(item: fake)
        controller.setEnabled(true)
        XCTAssertTrue(fake.enabled)
        XCTAssertTrue(controller.isEnabled)
        XCTAssertNil(controller.lastError)
    }

    func testDisablingUnregisters() {
        let fake = FakeLoginItem(enabled: true)
        let controller = LoginItemController(item: fake)
        controller.setEnabled(false)
        XCTAssertFalse(fake.enabled)
        XCTAssertFalse(controller.isEnabled)
    }

    func testRejectedChangeLeavesTheToggleWhereTheSystemHasIt() {
        // What happens when the app runs from a location the system refuses to
        // register: the switch must snap back rather than claim success.
        let fake = FakeLoginItem(enabled: false, failure: FakeError.refused)
        let controller = LoginItemController(item: fake)
        controller.setEnabled(true)
        XCTAssertFalse(controller.isEnabled)
        XCTAssertEqual(controller.lastError, FakeError.refused.localizedDescription)
    }

    func testASuccessfulChangeClearsAnEarlierError() {
        let fake = FakeLoginItem(enabled: false, failure: FakeError.refused)
        let controller = LoginItemController(item: fake)
        controller.setEnabled(true)
        XCTAssertNotNil(controller.lastError)

        fake.failure = nil
        controller.setEnabled(true)
        XCTAssertNil(controller.lastError)
        XCTAssertTrue(controller.isEnabled)
    }

    func testRefreshPicksUpAChangeMadeOutsideTheApp() {
        let fake = FakeLoginItem(enabled: false)
        let controller = LoginItemController(item: fake)
        fake.enabled = true  // the user ticked it in System Settings
        XCTAssertFalse(controller.isEnabled, "not observed until refreshed")
        controller.refresh()
        XCTAssertTrue(controller.isEnabled)
    }
}

private enum FakeError: LocalizedError {
    case refused
    var errorDescription: String? { "Operation not permitted" }
}

@MainActor
private final class FakeLoginItem: LoginItemManaging {
    var enabled: Bool
    var failure: Error?

    init(enabled: Bool, failure: Error? = nil) {
        self.enabled = enabled
        self.failure = failure
    }

    var isEnabled: Bool { enabled }

    func setEnabled(_ enabled: Bool) throws {
        if let failure { throw failure }
        self.enabled = enabled
    }
}
