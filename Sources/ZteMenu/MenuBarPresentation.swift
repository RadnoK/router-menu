import Foundation

struct MenuBarPresentation: Equatable {
    let isVisible: Bool
    let symbolName: String
    let variableValue: Double
    /// Text rendered next to the icon, or `nil` when the label is icon-only —
    /// because the user turned the percentage off, or the modem reported no
    /// battery reading to show.
    let batteryText: String?

    /// - Parameter showBatteryPercent: the user's preference; when false the
    ///   label carries no text at all, keeping the menu bar as narrow as before.
    static func make(for state: AppState, showBatteryPercent: Bool = false) -> MenuBarPresentation {
        func presentation(symbolName: String, variableValue: Double, battery: Int? = nil) -> MenuBarPresentation {
            MenuBarPresentation(isVisible: true,
                                symbolName: symbolName,
                                variableValue: variableValue,
                                batteryText: showBatteryPercent ? battery.map { "\($0)%" } : nil)
        }
        switch state {
        case .hidden:
            return MenuBarPresentation(isVisible: false,
                                       symbolName: "cellularbars",
                                       variableValue: 0,
                                       batteryText: nil)
        case .connected(let d):
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
