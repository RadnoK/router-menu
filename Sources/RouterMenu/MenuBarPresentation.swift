import Foundation

struct MenuBarPresentation: Equatable {
    let isVisible: Bool
    let symbolName: String
    let variableValue: Double
    /// Text rendered next to the icon, or `nil` when the label is icon-only —
    /// because the user turned the percentage off, or the modem reported no
    /// battery reading to show.
    let batteryText: String?

    /// - Parameters:
    ///   - showBatteryPercent: the user's preference; when false the label
    ///     carries no text at all, keeping the menu bar as narrow as before.
    ///   - showWhenDisconnected: keeps the icon in the menu bar while the modem
    ///     is out of reach, so the app stays reachable — its popover explains
    ///     the missing connection and offers the settings window.
    ///   - isTether: a phone sharing its connection. Like a wired router it has
    ///     no bars to grade, but it is not a router — it gets its own symbol.
    static func make(for state: AppState,
                     showBatteryPercent: Bool = false,
                     showWhenDisconnected: Bool = false,
                     showsRadioSignal: Bool = true,
                     isTether: Bool = false) -> MenuBarPresentation {
        func presentation(symbolName: String, variableValue: Double, battery: Int? = nil) -> MenuBarPresentation {
            MenuBarPresentation(isVisible: true,
                                symbolName: symbolName,
                                variableValue: variableValue,
                                batteryText: showBatteryPercent ? battery.map { "\($0)%" } : nil)
        }
        switch state {
        case .hidden:
            guard showWhenDisconnected else {
                return MenuBarPresentation(isVisible: false,
                                           symbolName: "cellularbars",
                                           variableValue: 0,
                                           batteryText: nil)
            }
            // Nothing was read from the modem, so there is no battery level to
            // put next to the icon regardless of the percentage preference.
            return presentation(symbolName: "antenna.radiowaves.left.and.right.slash",
                                variableValue: 0)
        case .connected(let d):
            guard showsRadioSignal else {
                // Neither has bars to grade, but they are different objects:
                // a tethered phone is not the household router.
                return presentation(symbolName: isTether ? "personalhotspot" : "wifi.router",
                                    variableValue: 0,
                                    battery: d.batteryPercent)
            }
            if d.signalBars <= 0 {
                return presentation(symbolName: "antenna.radiowaves.left.and.right.slash",
                                    variableValue: 0,
                                    battery: d.batteryPercent)
            }
            return presentation(symbolName: "cellularbars",
                                variableValue: Double(min(d.signalBars, 5)) / 5.0,
                                battery: d.batteryPercent)
        case .locationDenied, .error:
            // No connection means no battery reading — the icon stands alone.
            return presentation(symbolName: "antenna.radiowaves.left.and.right.slash",
                                variableValue: 0)
        }
    }
}
