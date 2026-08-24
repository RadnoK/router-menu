import XCTest
@testable import ZteMenu

/// Every slot these tests touch is a throwaway UUID (or the fake legacy
/// account below) — the suite must never read or write a real credential.
final class KeychainTests: XCTestCase {
    private let fakeLegacy = "test-legacy-\(UUID().uuidString)"
    private var ids: [UUID] = []

    private func freshID() -> UUID {
        let id = UUID()
        ids.append(id)
        return id
    }

    override func tearDown() {
        for id in ids { Keychain.deletePassword(for: id) }
        Keychain.deleteItem(account: fakeLegacy)
        super.tearDown()
    }

    func testSetGetDeletePerProfile() {
        let id = freshID()
        XCTAssertNil(Keychain.password(for: id))
        Keychain.setPassword("tajne", for: id)
        XCTAssertEqual(Keychain.password(for: id), "tajne")
        Keychain.setPassword("nowe", for: id)
        XCTAssertEqual(Keychain.password(for: id), "nowe")
        Keychain.deletePassword(for: id)
        XCTAssertNil(Keychain.password(for: id))
    }

    func testSlotsAreIndependent() {
        let a = freshID(), b = freshID()
        Keychain.setPassword("a", for: a)
        Keychain.setPassword("b", for: b)
        XCTAssertEqual(Keychain.password(for: a), "a")
        XCTAssertEqual(Keychain.password(for: b), "b")
    }

    func testLegacyMigrationCopiesOnceAndDeletesTheSource() {
        let id = freshID()
        Keychain.setItem("stare-haslo", account: fakeLegacy)
        Keychain.migrateLegacyPassword(from: fakeLegacy, to: id)
        XCTAssertEqual(Keychain.password(for: id), "stare-haslo")
        XCTAssertNil(Keychain.item(account: fakeLegacy), "the source item is gone")
        // Idempotent: a second call with nothing to migrate changes nothing.
        Keychain.migrateLegacyPassword(from: fakeLegacy, to: id)
        XCTAssertEqual(Keychain.password(for: id), "stare-haslo")
    }

    func testLegacyMigrationNeverOverwritesAnOccupiedSlot() {
        let id = freshID()
        Keychain.setPassword("juz-ustawione", for: id)
        Keychain.setItem("stare-haslo", account: fakeLegacy)
        Keychain.migrateLegacyPassword(from: fakeLegacy, to: id)
        XCTAssertEqual(Keychain.password(for: id), "juz-ustawione")
        XCTAssertNil(Keychain.item(account: fakeLegacy),
                     "the legacy item is still retired so migration stays one-shot")
    }
}
