import SwiftUI

public struct SettingsView: View {
    @Bindable private var settings: SettingsStore
    @Bindable private var updater: UpdaterController
    @State private var password: String = Keychain.password() ?? ""
    @State private var currentSSID: String = CoreWLANReader().currentSSID() ?? "—"

    public init(settings: SettingsStore, updater: UpdaterController) {
        self.settings = settings
        self.updater = updater
    }

    public var body: some View {
        Form {
            Section("Sieć") {
                Picker("Tryb wykrywania", selection: $settings.settings.networkMode) {
                    Text("Po nazwie WiFi").tag(NetworkMode.bySSID)
                    Text("Po osiągalności IP").tag(NetworkMode.byIPReachable)
                }
                LabeledContent("Aktualna sieć", value: currentSSID)
                TextField("Nazwa sieci ZTE", text: $settings.settings.ssid)
                TextField("IP modemu", text: $settings.settings.modemIP)
            }
            Section("Statystyki w panelu") {
                Toggle("Bateria, sygnał, sieć, operator", isOn: $settings.settings.stats.basic)
                Toggle("Szczegóły radiowe (RSRP/SINR)", isOn: $settings.settings.stats.radio)
                Toggle("Transfer", isOn: $settings.settings.stats.transfer)
                Toggle("Czas połączenia", isOn: $settings.settings.stats.uptime)
            }
            Section("Konto modemu (dla liczników transferu)") {
                SecureField("Hasło do panelu", text: $password)
                HStack {
                    Button("Zapisz hasło") { Keychain.setPassword(password) }
                    Button("Usuń") { Keychain.deletePassword(); password = "" }
                }
            }
            Section("Aktualizacje") {
                LabeledContent("Wersja", value: Self.appVersion)
                Toggle("Sprawdzaj automatycznie", isOn: $updater.automaticallyChecksForUpdates)
                if updater.automaticallyChecksForUpdates {
                    Picker("Częstotliwość", selection: $updater.updateCheckInterval) {
                        Text("Codziennie").tag(TimeInterval(86_400))
                        Text("Co tydzień").tag(TimeInterval(604_800))
                    }
                    Toggle("Pobieraj i instaluj automatycznie",
                           isOn: $updater.automaticallyDownloadsUpdates)
                }
                HStack {
                    Button("Sprawdź teraz") { updater.checkForUpdates() }
                        .disabled(!updater.canCheckForUpdates)
                    Spacer()
                    Text(Self.lastCheckLabel(updater.lastUpdateCheckDate))
                        .foregroundStyle(.secondary)
                        .font(.callout)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 380, height: 560)
    }

    static var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
    }

    static func lastCheckLabel(_ date: Date?) -> String {
        guard let date else { return "Nie sprawdzano" }
        let f = RelativeDateTimeFormatter()
        f.locale = Locale(identifier: "pl_PL")
        return "Sprawdzono \(f.localizedString(for: date, relativeTo: Date()))"
    }
}
