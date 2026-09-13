import XCTest
import SwiftUI
import AppKit
@testable import RouterMenu

/// Renders the widget offscreen at the real macOS widget sizes and writes PNGs
/// to /tmp/router-widget/. Like `PopoverRenderHarness`, this exists so layout
/// can be SEEN without installing the extension, registering an App Group, or
/// waiting on WidgetKit to schedule a timeline. Run explicitly:
///     swift test --filter WidgetRenderHarness
@MainActor
final class WidgetRenderHarness: XCTestCase {
    /// macOS widget point sizes.
    private func size(_ family: WidgetLayoutFamily) -> CGSize {
        switch family {
        case .small: return CGSize(width: 155, height: 155)
        case .medium: return CGSize(width: 329, height: 155)
        case .large: return CGSize(width: 329, height: 345)
        }
    }

    private let now = Date(timeIntervalSince1970: 1_756_000_000)

    private func history(hours: Int = 24, drain: Bool = true) -> [WidgetSnapshot.Point] {
        let series: [(Date, Double)] = (0..<(hours * 6)).map { i in
            let t = now.addingTimeInterval(Double(i - hours * 6) * 600)
            let v = drain ? max(8, 95 - Double(i) * 0.55) : 70 + sin(Double(i) / 6) * 12
            return (t, v)
        }
        return WidgetHistoryDownsample.reduce(series)
    }

    private func snapshot(battery: Int? = 61,
                          charging: Bool = false,
                          bars: Int = 4,
                          online: Bool = true,
                          age: TimeInterval = 0,
                          points: [WidgetSnapshot.Point]? = nil) -> WidgetSnapshot {
        WidgetSnapshot(capturedAt: now.addingTimeInterval(-age),
                       deviceName: "ZTE U50",
                       batteryPercent: battery, isCharging: charging,
                       signalBars: bars, networkLabel: "5G",
                       rsrp: -93, sinr: 12.4,
                       rxSpeed: 5_871_000, txSpeed: 912_000,
                       sessionRx: 1_008_395_299, sessionTx: 350_536_546,
                       batteryHistory: points ?? history(),
                       isOnline: online)
    }

    @discardableResult
    private func render(_ snapshot: WidgetSnapshot?,
                        family: WidgetLayoutFamily,
                        name: String,
                        dark: Bool) -> NSImage? {
        let freshness = snapshot.map { WidgetFreshness.of($0.capturedAt, now: now) } ?? .stale
        let view = WidgetContentView(snapshot: snapshot, freshness: freshness,
                                     family: family, now: now)
            .padding(family == .small ? 12 : 16)
            .frame(width: size(family).width, height: size(family).height)
            .environment(\.colorScheme, dark ? .dark : .light)
            // WidgetKit supplies the material background; ImageRenderer cannot
            // draw it outside a window, so stand in a flat equivalent.
            .background(dark ? Color(white: 0.13) : Color(white: 0.97))

        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        guard let image = renderer.nsImage,
              let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else {
            XCTFail("render produced no image for \(name)")
            return nil
        }
        let dir = URL(fileURLWithPath: "/tmp/router-widget", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("\(name)-\(dark ? "dark" : "light").png")
        try? png.write(to: url)
        print("rendered \(url.path) (\(Int(image.size.width))×\(Int(image.size.height)))")
        return image
    }

    func testRenderAllFamilies() {
        for family in WidgetLayoutFamily.allCases {
            for dark in [false, true] {
                render(snapshot(), family: family, name: "\(family)", dark: dark)
            }
        }
    }

    func testRenderEdgeStates() {
        render(snapshot(battery: 8, bars: 1), family: .small, name: "low-battery", dark: true)
        render(snapshot(battery: 34, charging: true), family: .small, name: "charging", dark: true)
        render(snapshot(battery: nil, bars: 0, online: false),
               family: .medium, name: "no-battery-offline", dark: true)
        render(snapshot(age: 9 * 60), family: .medium, name: "aging", dark: true)
        render(snapshot(age: 5 * 3600), family: .medium, name: "stale", dark: true)
        render(snapshot(points: []), family: .large, name: "no-history", dark: true)
        render(nil, family: .medium, name: "empty", dark: true)
        render(nil, family: .small, name: "empty-small", dark: true)
    }

    /// A long device name must not push the layout around or truncate the
    /// battery number — the reading is the point of the widget.
    func testRenderLongDeviceName() {
        let long = WidgetSnapshot(capturedAt: now,
                                  deviceName: "ZTE MU5001 Living Room Upstairs",
                                  batteryPercent: 100, isCharging: true, signalBars: 5,
                                  networkLabel: "5G", rsrp: -78, sinr: 22.5,
                                  rxSpeed: 125_000_000, txSpeed: 25_000_000,
                                  sessionRx: 98_765_432_100, sessionTx: 12_345_678_900,
                                  batteryHistory: history(drain: false), isOnline: true)
        for family in WidgetLayoutFamily.allCases {
            render(long, family: family, name: "long-name-\(family)", dark: true)
        }
    }
}
