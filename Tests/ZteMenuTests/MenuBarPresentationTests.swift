import XCTest
@testable import ZteMenu

final class MenuBarPresentationTests: XCTestCase {
    private func data(bars: Int) -> ModemData {
        ModemData.parse(["signalbar": "\(bars)", "network_type": "ENDC", "ppp_status": "ppp_connected"])
    }

    func testHiddenIsInvisible() {
        XCTAssertFalse(MenuBarPresentation.make(for: .hidden).isVisible)
    }

    func testConnectedUsesCellularbars() {
        let p = MenuBarPresentation.make(for: .connected(data(bars: 4)))
        XCTAssertTrue(p.isVisible)
        XCTAssertEqual(p.symbolName, "cellularbars")
        XCTAssertEqual(p.variableValue, 0.8, accuracy: 0.001) // 4/5
    }

    func testNoSignalUsesSlashSymbol() {
        let p = MenuBarPresentation.make(for: .connected(data(bars: 0)))
        XCTAssertEqual(p.symbolName, "antenna.radiowaves.left.and.right.slash")
    }

    func testErrorIsVisibleWithSlash() {
        let p = MenuBarPresentation.make(for: .error(.unreachable))
        XCTAssertTrue(p.isVisible)
        XCTAssertEqual(p.symbolName, "antenna.radiowaves.left.and.right.slash")
    }

    func testLocationDeniedIsVisible() {
        XCTAssertTrue(MenuBarPresentation.make(for: .locationDenied).isVisible)
    }
}
