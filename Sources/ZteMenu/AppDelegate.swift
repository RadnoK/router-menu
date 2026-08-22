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
    /// oraz widok popovera i okna ustawień.
    public let settings = SettingsStore()
    public let updater = UpdaterController()
    public let history = HistoryStore()
    public lazy var store = ModemStore(settings: settings, history: history)
    private let permission = LocationPermission()
    private var refreshTask: Task<Void, Never>?

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

    /// Aplikacja menu bar NIE może zamykać się, gdy zamknie się okno ustawień.
    /// Domyślnie SwiftUI z sceną `Window` zwraca tu `true` i kończy proces, gdy
    /// nie ma otwartych okien — przez co ikona „znika" po chwili. Menu bar żyje
    /// niezależnie od okien, więc zwracamy `false`.
    public func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}
