import Foundation
import Observation

@MainActor
@Observable
public final class SettingsStore {
    var settings: AppSettings {
        didSet { save() }
    }
    private let defaults: UserDefaults
    private let key = "zte.settings"

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: key),
           let loaded = try? JSONDecoder().decode(AppSettings.self, from: data) {
            settings = loaded
        } else {
            settings = AppSettings.defaults
        }
        // Persist immediately: a legacy payload migrates on first read, and
        // writing it back pins the migrated profile's UUID across launches.
        save()
    }

    func save() {
        if let data = try? JSONEncoder().encode(settings) {
            defaults.set(data, forKey: key)
        }
    }

    /// Which profile the settings window is editing. UI-session state, not
    /// persisted; nil (or a deleted id) falls back to the first profile.
    var editedProfileID: UUID?

    var profile: ModemProfile {
        get {
            settings.profiles.first { $0.id == editedProfileID } ?? settings.profiles[0]
        }
        set {
            // Writes for a profile that no longer exists are dropped on
            // purpose — a stale copy captured across a removal must not
            // resurrect the device.
            guard let index = settings.profiles.firstIndex(where: { $0.id == newValue.id })
            else { return }
            settings.profiles[index] = newValue
        }
    }
}
