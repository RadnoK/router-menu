import Foundation

enum AsusProvider {
    static let descriptor = ProviderDescriptor(
        displayName: "Asus",
        defaultBaseURL: URL(string: "http://192.168.50.1")!,   // Asuswrt default
        defaultSSID: "",
        supportedMatchModes: [.ssid, .ipProbe],
        defaultMatchMode: .ipProbe,
        capabilities: ModemCapabilities(hasBattery: false,
                                        passwordRole: .requiredForAll,
                                        needsUsername: true,
                                        hasRadioSignal: false),
        makeDriver: { profile, password, http in
            AsusClient(baseURL: profile.baseURL,
                       username: profile.username,
                       password: password,
                       http: http)
        }
    )
}
