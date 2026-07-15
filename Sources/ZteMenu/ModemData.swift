import Foundation

struct ModemData: Equatable {
    let batteryPercent: Int?
    let isCharging: Bool
    let signalBars: Int
    let networkType: String
    let provider: String?
    let rsrp: Int?
    let sinr: Double?
    let isOnline: Bool

    static func parse(_ raw: [String: String]) -> ModemData {
        func str(_ key: String) -> String? {
            guard let v = raw[key], !v.isEmpty else { return nil }
            return v
        }
        return ModemData(
            batteryPercent: str("battery_value").flatMap { Int($0) },
            isCharging: raw["battery_charging"] == "1",
            signalBars: str("signalbar").flatMap { Int($0) } ?? 0,
            networkType: str("network_type") ?? "",
            provider: str("network_provider"),
            rsrp: str("Z5g_rsrp").flatMap { Int($0) },
            sinr: str("Z5g_SINR").flatMap { Double($0) },
            isOnline: raw["ppp_status"] == "ppp_connected"
        )
    }

    var networkLabel: String {
        switch networkType {
        case "ENDC": return "5G"
        case "": return "—"
        default: return networkType
        }
    }

    var signalDescription: String {
        switch signalBars {
        case ...0: return "Brak"
        case 1: return "Bardzo słaby"
        case 2: return "Słaby"
        case 3: return "Średni"
        case 4: return "Dobry"
        default: return "Bardzo dobry"
        }
    }
}
