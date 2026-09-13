import XCTest
import AppKit
import SwiftUI
@testable import RouterMenu

final class WidgetBatteryStyleTests: XCTestCase {
    private func symbol(_ percent: Int?, charging: Bool = false) -> String {
        WidgetBatteryStyle.symbolName(percent: percent, isCharging: charging)
    }

    /// A name SF Symbols does not ship renders as a blank rectangle in the
    /// widget, and nothing else in the pipeline would catch it — the widget
    /// host draws it silently. Two names in the first draft were invented.
    func testEverySymbolNameExistsInThisSFSymbolsRelease() {
        var names = Set<String>()
        for p in [nil, 0, 5, 12, 13, 20, 37, 38, 50, 62, 63, 75, 87, 88, 100] as [Int?] {
            names.insert(symbol(p))
            names.insert(symbol(p, charging: true))
        }
        for bars in -1...5 { names.insert(WidgetBatteryStyle.signalSymbol(bars: bars)) }
        for name in names {
            XCTAssertNotNil(NSImage(systemSymbolName: name, accessibilityDescription: nil),
                            "SF Symbol '\(name)' does not exist")
        }
    }

    func testNoReadingUsesTheUnavailableGlyph() {
        XCTAssertEqual(symbol(nil), "minus.plus.batteryblock.slash")
    }

    func testChargingAlwaysShowsTheBoltGlyph() {
        XCTAssertEqual(symbol(5, charging: true), "battery.100percent.bolt")
        XCTAssertEqual(symbol(95, charging: true), "battery.100percent.bolt")
    }

    func testFillStepsFollowTheLevel() {
        XCTAssertEqual(symbol(0), "battery.0percent")
        XCTAssertEqual(symbol(25), "battery.25percent")
        XCTAssertEqual(symbol(50), "battery.50percent")
        XCTAssertEqual(symbol(75), "battery.75percent")
        XCTAssertEqual(symbol(100), "battery.100percent")
    }

    func testLowBatteryIsRedAndMidIsOrange() {
        XCTAssertEqual(WidgetBatteryStyle.tint(percent: 10, isCharging: false), .red)
        XCTAssertEqual(WidgetBatteryStyle.tint(percent: 25, isCharging: false), .orange)
        XCTAssertEqual(WidgetBatteryStyle.tint(percent: 80, isCharging: false), .green)
    }

    /// A level that is climbing is not a warning, so charging stays green.
    func testChargingIsGreenEvenWhenLow() {
        XCTAssertEqual(WidgetBatteryStyle.tint(percent: 3, isCharging: true), .green)
    }

    func testMissingReadingRendersAsADashNotZero() {
        XCTAssertEqual(WidgetBatteryStyle.percentText(nil), "—")
        XCTAssertEqual(WidgetBatteryStyle.percentText(0), "0%")
    }
}
