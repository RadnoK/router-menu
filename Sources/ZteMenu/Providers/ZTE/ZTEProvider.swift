import Foundation

enum ZTEProvider {
    static let descriptor = ProviderDescriptor(
        displayName: "ZTE",
        defaultBaseURL: URL(string: "http://192.168.0.1")!,
        defaultSSID: "ZTE_B4B622",
        supportedMatchModes: [.ssid, .ipProbe],
        defaultMatchMode: .ssid,
        capabilities: ModemCapabilities(hasBattery: true,
                                        passwordRole: .unlocksTraffic,
                                        needsUsername: false,
                                        hasRadioSignal: true),
        makeDriver: { profile, password, http in
            ZTEClient(baseURL: profile.baseURL, http: http, password: password)
        }
    )
}
