import XCTest
@testable import ZteMenu

@MainActor
final class L10nTests: XCTestCase {
    func testMissingKeyFallsBackToRawValue() {
        // No bundles at all: every lookup degrades to the key itself, which is
        // visible in the UI instead of crashing or rendering empty.
        let l10n = L10n(language: .en, bundles: [])
        XCTAssertEqual(l10n(.popoverRefresh), LocKey.popoverRefresh.rawValue)
    }

    func testLocaleTracksResolvedLanguage() {
        let l10n = L10n(language: .pl, bundles: [])
        XCTAssertEqual(l10n.locale.identifier, "pl")
        l10n.setLanguage(.en)
        XCTAssertEqual(l10n.locale.identifier, "en")
    }

    func testSetLanguageChangesResolvedCode() {
        let l10n = L10n(language: .en, bundles: [])
        XCTAssertEqual(l10n.resolvedCode, "en")
        l10n.setLanguage(.pl)
        XCTAssertEqual(l10n.resolvedCode, "pl")
    }

    func testFormattingSubstitutesArguments() {
        let l10n = L10n(language: .en, bundles: [])
        // With no table the format string is the raw key, which contains no
        // placeholder, so the argument is dropped rather than corrupting output.
        XCTAssertEqual(l10n(.settingsLastChecked, "2 hours ago"),
                       LocKey.settingsLastChecked.rawValue)
    }

    func testSetLanguagePropagatesToResolvedStrings() {
        // The core behaviour of the feature: switching the language must
        // actually change what callAsFunction returns for a real key, using
        // the bundled .lproj tables (via the default Bundle.module lookup).
        let l10n = L10n(language: .en)
        XCTAssertEqual(l10n(.popoverRefresh), "Refresh")
        l10n.setLanguage(.pl)
        XCTAssertEqual(l10n(.popoverRefresh), "Odśwież")
    }

    func testEveryKeyResolvesInBothLanguages() throws {
        // The real guard: catches a key added to LocKey but forgotten in a
        // .strings file, and a typo in either file.
        for code in ["en", "pl"] {
            let table = try Self.loadStrings(code: code)
            for key in LocKey.allCases {
                XCTAssertNotNil(table[key.rawValue],
                                "missing \(key.rawValue) in \(code).lproj/Localizable.strings")
            }
            XCTAssertEqual(table.count, LocKey.allCases.count,
                           "\(code).lproj has entries not present in LocKey")
        }
    }

    /// Reads the shipped .strings file straight from the repository, so the test
    /// verifies the file that actually gets bundled rather than a copy.
    static func loadStrings(code: String) throws -> [String: String] {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // ZteMenuTests
            .deletingLastPathComponent()   // Tests
            .deletingLastPathComponent()   // repo root
            .appendingPathComponent("Resources/\(code).lproj/Localizable.strings")
        let data = try Data(contentsOf: url)
        let plist = try PropertyListSerialization.propertyList(from: data, format: nil)
        return try XCTUnwrap(plist as? [String: String])
    }
}
