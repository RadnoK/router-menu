import SwiftUI

public struct SettingsView: View {
    @Bindable private var settings: SettingsStore
    @State private var password: String = Keychain.password() ?? ""
    @State private var currentSSID: String = CoreWLANReader().currentSSID() ?? "—"

    public init(settings: SettingsStore) {
        self.settings = settings
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
        }
        .formStyle(.grouped)
        .frame(width: 380, height: 420)
    }
}
