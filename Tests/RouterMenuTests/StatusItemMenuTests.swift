import XCTest
import AppKit
@testable import RouterMenu

/// The right-click menu on the menu bar icon. `MenuBarExtra` owns the left
/// click (it opens the popover), so the secondary menu is built by hand and
/// its contents are worth pinning down.
@MainActor
final class StatusItemMenuTests: XCTestCase {
    func testTheMenuOffersQuit() {
        let l10n = L10n(language: .en, bundles: [])
        let menu = StatusItemMenu.make(l10n: l10n)
        let titles = menu.items.map(\.title)
        XCTAssertTrue(titles.contains(l10n(.popoverQuit)), "got \(titles)")
    }

    /// Cmd-Q is what a user reaches for; the menu should say so rather than
    /// leaving the shortcut undiscoverable.
    func testQuitCarriesTheStandardShortcut() {
        let menu = StatusItemMenu.make(l10n: L10n(language: .en, bundles: []))
        let quit = menu.items.first { $0.action == #selector(NSApplication.terminate(_:)) }
        XCTAssertEqual(quit?.keyEquivalent, "q")
        XCTAssertEqual(quit?.keyEquivalentModifierMask, .command)
    }

    /// A menu item with no target falls back to the responder chain, which is
    /// what actually lets `terminate(_:)` reach NSApp.
    func testQuitIsWiredToTerminate() {
        let menu = StatusItemMenu.make(l10n: L10n(language: .en, bundles: []))
        let quit = menu.items.first { $0.title == "popover.quit" }
        XCTAssertEqual(quit?.action, #selector(NSApplication.terminate(_:)))
    }

    /// The menu is rebuilt per click so it picks up a language change without
    /// the app being restarted.
    func testTheMenuIsLocalizedAtBuildTime() throws {
        let resources = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("Resources")
        let bundle = try XCTUnwrap(Bundle(path: resources.path))
        let pl = StatusItemMenu.make(l10n: L10n(language: .pl, bundles: [bundle]))
        XCTAssertEqual(pl.items.first?.title, "Zakończ")
    }
}
