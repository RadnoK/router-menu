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
    public lazy var l10n = L10n(language: settings.settings.language)
    public lazy var store = ModemStore(settings: settings, history: history)
    private let permission = LocationPermission()
    private var refreshTask: Task<Void, Never>?

    public func applicationDidFinishLaunching(_ notification: Notification) {
        l10n.setLanguage(settings.settings.language)
        // A location-permission change (e.g. the user taps "Allow") must refresh
        // state IMMEDIATELY — otherwise the icon would only appear on the next
        // loop tick, up to 60 s later. Verified live: permission settles ~3 s
        // after launch, after which the state flips to connected.
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
