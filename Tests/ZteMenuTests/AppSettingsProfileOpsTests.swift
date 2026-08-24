import XCTest
@testable import ZteMenu

final class AppSettingsProfileOpsTests: XCTestCase {
    func testAddProfileAppendsTheRequestedProviderAndReturnsItsId() {
        var s = AppSettings()
        let id = s.addProfile(provider: .zte)
        XCTAssertEqual(s.profiles.count, 2)
        XCTAssertEqual(s.profiles.last?.id, id)
        XCTAssertEqual(s.profiles.last?.provider, .zte)
    }

    func testRemoveProfileRefusesTheLastOne() {
        var s = AppSettings()
        XCTAssertFalse(s.removeProfile(id: s.profiles[0].id))
        XCTAssertEqual(s.profiles.count, 1, "the never-empty invariant holds")
    }

    func testRemoveProfileRemovesByIdWhenOthersRemain() {
        var s = AppSettings()
        let added = s.addProfile(provider: .zte)
        XCTAssertTrue(s.removeProfile(id: s.profiles[0].id))
        XCTAssertEqual(s.profiles.map(\.id), [added])
    }

    func testRemoveProfileWithUnknownIdChangesNothing() {
        var s = AppSettings()
        _ = s.addProfile(provider: .zte)
        XCTAssertFalse(s.removeProfile(id: UUID()))
        XCTAssertEqual(s.profiles.count, 2)
    }

    func testMoveProfilesReordersMatcherPriority() {
        var s = AppSettings()
        let second = s.addProfile(provider: .zte)
        s.moveProfiles(fromOffsets: IndexSet(integer: 1), toOffset: 0)
        XCTAssertEqual(s.profiles.first?.id, second)
    }
}
