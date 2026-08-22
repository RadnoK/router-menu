import XCTest
@testable import ZteMenu

final class AppLanguageTests: XCTestCase {
    func testExplicitLanguageIgnoresSystemPreferences() {
        XCTAssertEqual(AppLanguage.resolvedCode(for: .pl, preferred: ["en-US"]), "pl")
        XCTAssertEqual(AppLanguage.resolvedCode(for: .en, preferred: ["pl-PL"]), "en")
    }

    func testSystemResolvesPolishPreferenceToPolish() {
        XCTAssertEqual(AppLanguage.resolvedCode(for: .system, preferred: ["pl-PL", "en-US"]), "pl")
        XCTAssertEqual(AppLanguage.resolvedCode(for: .system, preferred: ["pl"]), "pl")
    }

    func testSystemFallsBackToEnglishForOtherLanguages() {
        XCTAssertEqual(AppLanguage.resolvedCode(for: .system, preferred: ["de-DE", "pl-PL"]), "en")
        XCTAssertEqual(AppLanguage.resolvedCode(for: .system, preferred: []), "en")
    }

    func testAllCasesAreStableRawValues() {
        XCTAssertEqual(AppLanguage.allCases.map(\.rawValue), ["system", "pl", "en"])
    }
}
