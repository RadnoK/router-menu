import AppKit
import SwiftUI

/// Steruje cyklem życia aplikacji: trzyma współdzielony `ModemStore`,
/// prosi o uprawnienia lokalizacji i prowadzi pętlę odświeżania — wszystko
/// niezależnie od widoczności ikony na pasku menu.
///
/// Bootstrap MUSI żyć tutaj, a nie w widoku zawartości menu: `MenuBarExtra`
/// renderuje swoją zawartość (i jej `.task`) dopiero po otwarciu menu, a menu
/// nie da się otworzyć, gdy ikona jest ukryta (stan startowy `.hidden`). Gdyby
/// pętla żyła w widoku, nigdy by nie wystartowała.
@MainActor
public final class AppDelegate: NSObject, NSApplicationDelegate {
    /// Współdzielone, obserwowalne źródło prawdy — czyta je etykieta ikony
    /// oraz widok menu.
    private let settings: SettingsStore
    private let history: HistoryStore
    public let store: ModemStore
    private let permission = LocationPermission()
    private var refreshTask: Task<Void, Never>?

    override public init() {
        let settings = SettingsStore()
        let history = HistoryStore()
        self.settings = settings
        self.history = history
        self.store = ModemStore(settings: settings, history: history)
        super.init()
    }

    public func applicationDidFinishLaunching(_ notification: Notification) {
        // Zmiana uprawnień lokalizacji (np. użytkownik klika „Zezwól") musi
        // NATYCHMIAST odświeżyć stan — inaczej ikona pojawiłaby się dopiero
        // przy kolejnym ticku pętli (do 60 s później). Zweryfikowane na żywo:
        // zgoda ustala się ~3 s po starcie, po czym stan przeskakuje na connected.
        permission.onChange = { [weak self] auth in
            self?.store.setLocationAuth(auth)
            self?.triggerRefresh()
        }
        store.setLocationAuth(permission.status)
        permission.requestIfNeeded()
        startRefreshLoop()
    }

    private func startRefreshLoop() {
        refreshTask?.cancel()
        refreshTask = Task { [store] in
            await store.refresh()
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(Config.refreshInterval))
                await store.refresh()
            }
        }
    }

    private func triggerRefresh() {
        Task { [store] in await store.refresh() }
    }

    public func applicationWillTerminate(_ notification: Notification) {
        refreshTask?.cancel()
    }
}
