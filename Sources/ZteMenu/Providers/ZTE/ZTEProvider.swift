import Foundation

enum ZTEProvider {
    static let descriptor = ProviderDescriptor(
        displayName: "ZTE",
        defaultBaseURL: URL(string: "http://192.168.0.1")!,
        defaultSSID: "ZTE_B4B622",
        supportedMatchModes: [.ssid, .ipProbe],
        defaultMatchMode: .ssid,
        capabilities: ModemCapabilities(hasBattery: true, passwordRole: .unlocksTraffic),
        makeDriver: { baseURL, password, http in
            ZTEClient(baseURL: baseURL, http: http, password: password)
        }
    )
}
