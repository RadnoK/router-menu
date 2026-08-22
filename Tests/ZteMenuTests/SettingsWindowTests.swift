import XCTest
import AppKit
@testable import ZteMenu

/// Guards the mechanism that opens the settings window from the popover.
///
/// A previous version called `showSettingsWindow:` on `NSApplication`. That
/// selector is not implemented by `NSApplication` — SwiftUI binds the Settings
/// scene's menu item internally — so the button silently did nothing. These
/// tests pin the assumptions that made the old approach fail.
@MainActor
final class SettingsWindowTests: XCTestCase {
    func testNSApplicationDoesNotImplementSettingsSelectors() {
        // If a future macOS ever does implement these, this test fails and we
        // can reconsider using them. Until then, relying on them is a bug.
        XCTAssertFalse(NSApplication.shared.responds(to: Selector(("showSettingsWindow:"))))
        XCTAssertFalse(NSApplication.shared.responds(to: Selector(("showPreferencesWindow:"))))
    }

    func testSettingsWindowIDIsStable() {
        // The popover opens the window by ID; the scene must declare the same
        // one. A typo on either side reproduces the "nothing happens" bug.
        XCTAssertEqual(ZteMenuApp.settingsWindowID, "settings")
    }
}
