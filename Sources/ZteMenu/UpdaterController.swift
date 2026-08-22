import Foundation
import Observation
import Sparkle

/// Opakowuje Sparkle na potrzeby UI ustawień.
///
/// Preferencje (automatyczne sprawdzanie, interwał) trzyma sam Sparkle
/// w UserDefaults — nie duplikujemy ich w AppSettings, żeby nie mieć
/// dwóch rozjeżdżających się źródeł prawdy.
@MainActor
@Observable
public final class UpdaterController {
    private let controller: SPUStandardUpdaterController

    /// Podbijane po zmianie ustawień, żeby widok przeliczył właściwości
    /// czytane bezpośrednio ze Sparkle.
    private var revision = 0

    public init() {
        controller = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
    }

    private var updater: SPUUpdater { controller.updater }

    public var automaticallyChecksForUpdates: Bool {
        get {
            _ = revision
            return updater.automaticallyChecksForUpdates
        }
        set {
            updater.automaticallyChecksForUpdates = newValue
            revision += 1
        }
    }

    public var automaticallyDownloadsUpdates: Bool {
        get {
            _ = revision
            return updater.automaticallyDownloadsUpdates
        }
        set {
            updater.automaticallyDownloadsUpdates = newValue
            revision += 1
        }
    }

    /// Interwał sprawdzania w sekundach; Sparkle wymusza minimum 1 godziny.
    public var updateCheckInterval: TimeInterval {
        get {
            _ = revision
            return updater.updateCheckInterval
        }
        set {
            updater.updateCheckInterval = newValue
            revision += 1
        }
    }

    public var lastUpdateCheckDate: Date? {
        _ = revision
        return updater.lastUpdateCheckDate
    }

    public var canCheckForUpdates: Bool {
        _ = revision
        return updater.canCheckForUpdates
    }

    /// Ręczne sprawdzenie — pokazuje UI Sparkle także gdy nie ma nowej wersji.
    public func checkForUpdates() {
        updater.checkForUpdates()
        revision += 1
    }
}
