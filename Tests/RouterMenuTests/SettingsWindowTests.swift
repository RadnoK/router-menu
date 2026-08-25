import XCTest
import AppKit
@testable import RouterMenu

/// Guards how the popover opens the settings window.
///
/// The redesign first tried `showSettingsWindow:` on `NSApplication`; that
/// selector does not exist there, so the button silently did nothing. These
/// tests pin the facts that make `SettingsWindowOpener` the working route.
@MainActor
final class SettingsWindowTests: XCTestCase {
    func testNSApplicationDoesNotImplementSettingsSelectors() {
        // If a future macOS implements these, this fails and we can simplify.
        XCTAssertFalse(NSApplication.shared.responds(to: Selector(("showSettingsWindow:"))))
        XCTAssertFalse(NSApplication.shared.responds(to: Selector(("showPreferencesWindow:"))))
    }

    func testFindsSettingsItemByActionAndShortcut() {
        let menu = NSMenu()
        menu.addItem(withTitle: "About", action: Selector(("orderFrontStandardAboutPanel:")), keyEquivalent: "")
        let settings = menu.addItem(withTitle: "Settings…", action: Selector(("menuAction:")), keyEquivalent: ",")
        settings.keyEquivalentModifierMask = .command

        XCTAssertEqual(SettingsWindowOpener.settingsItemIndex(in: menu), 1)
    }

    func testFallsBackToShortcutWhenActionIsUnknown() {
        // SwiftUI's action name has changed across releases; the Command-,
        // shortcut is the stable signal.
        let menu = NSMenu()
        menu.addItem(withTitle: "About", action: nil, keyEquivalent: "")
        let settings = menu.addItem(withTitle: "Ustawienia…", action: Selector(("someFutureAction:")), keyEquivalent: ",")
        settings.keyEquivalentModifierMask = .command

        XCTAssertEqual(SettingsWindowOpener.settingsItemIndex(in: menu), 1)
    }

    func testReturnsNilWhenThereIsNoSettingsItem() {
        let menu = NSMenu()
        menu.addItem(withTitle: "About", action: nil, keyEquivalent: "")
        menu.addItem(withTitle: "Quit", action: nil, keyEquivalent: "q")

        XCTAssertNil(SettingsWindowOpener.settingsItemIndex(in: menu))
    }
}
