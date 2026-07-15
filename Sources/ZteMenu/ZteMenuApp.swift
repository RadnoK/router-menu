import SwiftUI

public struct ZteMenuApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    public init() {}

    public var body: some Scene {
        // Współdzielony store z AppDelegate jest jedynym źródłem prawdy:
        // AppDelegate go odświeża, a etykieta ikony i menu tylko go czytają.
        let store = appDelegate.store
        let p = MenuBarPresentation.make(for: store.state)
        return MenuBarExtra(isInserted: .constant(p.isVisible)) {
            MenuBarView(store: store)
        } label: {
            Image(systemName: p.symbolName, variableValue: p.variableValue)
        }
        .menuBarExtraStyle(.menu)
    }
}
