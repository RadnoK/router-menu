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
    }

    func save() {
        if let data = try? JSONEncoder().encode(settings) {
            defaults.set(data, forKey: key)
        }
    }

    var modemBaseURL: URL {
        URL(string: "http://\(settings.modemIP)") ?? Config.modemBaseURL
    }
}
