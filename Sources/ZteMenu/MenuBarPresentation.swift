import Foundation

struct MenuBarPresentation: Equatable {
    let isVisible: Bool
    let symbolName: String
    let variableValue: Double

    static func make(for state: AppState) -> MenuBarPresentation {
        switch state {
        case .hidden:
            return MenuBarPresentation(isVisible: false, symbolName: "cellularbars", variableValue: 0)
        case .connected(let d):
            if d.signalBars <= 0 {
                return MenuBarPresentation(isVisible: true,
                                           symbolName: "antenna.radiowaves.left.and.right.slash",
                                           variableValue: 0)
            }
            return MenuBarPresentation(isVisible: true,
                                       symbolName: "cellularbars",
                                       variableValue: Double(min(d.signalBars, 5)) / 5.0)
        case .locationDenied, .error:
            return MenuBarPresentation(isVisible: true,
                                       symbolName: "antenna.radiowaves.left.and.right.slash",
                                       variableValue: 0)
        }
    }
}
