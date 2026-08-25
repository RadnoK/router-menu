import XCTest
@testable import RouterMenu

/// The tab bar is hand-built, so these pin the parts a visual glance would
/// otherwise have to catch: every tab has its own icon and its own title.
final class SettingsTabTests: XCTestCase {
    func testTabOrderIsStable() {
        XCTAssertEqual(SettingsTab.allCases.map(\.rawValue),
                       ["general", "devices", "updates"])
    }

    func testEveryTabHasADistinctSymbol() {
        let symbols = SettingsTab.allCases.map(\.symbolName)
        XCTAssertEqual(Set(symbols).count, symbols.count, "tabs must not share an icon")
        XCTAssertFalse(symbols.contains(where: \.isEmpty))
    }

    func testEveryTabHasADistinctTitleKey() {
        let keys = SettingsTab.allCases.map(\.titleKey)
        XCTAssertEqual(Set(keys).count, keys.count, "tabs must not share a title")
    }

    @MainActor
    func testEveryTabTitleHasAnEntryInBothLanguages() throws {
        // L10n resolves against Bundle.main, which under `swift test` is the
        // XCTest runner and has no .lproj — so read the shipped tables directly,
        // the same way L10nTests does.
        for code in ["en", "pl"] {
            let table = try L10nTests.loadStrings(code: code)
            for tab in SettingsTab.allCases {
                let value = table[tab.titleKey.rawValue]
                XCTAssertNotNil(value, "\(tab) has no \(code) title")
                XCTAssertFalse(value?.isEmpty ?? true, "\(tab) \(code) title is empty")
            }
        }
    }
}
