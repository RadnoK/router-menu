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

    /// v1 manages exactly one device; the settings window edits this profile.
    var profile: ModemProfile {
        get { settings.profiles[0] }
        set { settings.profiles[0] = newValue }
    }

    var modemBaseURL: URL {
        URL(string: "http://\(settings.modemIP)") ?? Config.modemBaseURL
    }
}
