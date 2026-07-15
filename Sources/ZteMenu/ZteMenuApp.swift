import SwiftUI

public struct ZteMenuApp: App {
    @State private var store = ModemStore()

    public init() {}

    public var body: some Scene {
        let p = MenuBarPresentation.make(for: store.state)
        return MenuBarExtra(isInserted: .constant(p.isVisible)) {
            MenuBarView(store: store)
        } label: {
            Image(systemName: p.symbolName, variableValue: p.variableValue)
        }
        .menuBarExtraStyle(.menu)
    }
}
