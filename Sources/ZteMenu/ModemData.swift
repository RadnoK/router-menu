import Foundation

/// Signal strength as a value, not a sentence. Rendering it as text belongs to
/// the view layer, which knows the active language.
enum SignalQuality: Sendable, Equatable {
    // `noSignal`, not `none`: a case named `none` collides with `Optional.none`
    // during type inference, which breaks `XCTAssertEqual(x, .none)`.
    case noSignal, veryWeak, weak, medium, good, veryGood
}

struct ModemData: Equatable {
    let batteryPercent: Int?
    let isCharging: Bool
    let signalBars: Int
    let networkType: String
    let provider: String?
    let rsrp: Int?
    let sinr: Double?
    let isOnline: Bool
    let rxSpeed: Int?
    let txSpeed: Int?
    let sessionRx: Int?
    let sessionTx: Int?
    let totalRx: Int?
    let totalTx: Int?
    let monthlyRx: Int?
    let monthlyTx: Int?
    let sessionUptime: Int?
    let monthlyUptime: Int?

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
            isOnline: raw["ppp_status"] == "ppp_connected",
            rxSpeed: str("realtime_rx_thrpt").flatMap { Int($0) },
            txSpeed: str("realtime_tx_thrpt").flatMap { Int($0) },
            sessionRx: str("realtime_rx_bytes").flatMap { Int($0) },
            sessionTx: str("realtime_tx_bytes").flatMap { Int($0) },
            totalRx: str("total_rx_bytes").flatMap { Int($0) },
            totalTx: str("total_tx_bytes").flatMap { Int($0) },
            monthlyRx: str("monthly_rx_bytes").flatMap { Int($0) },
            monthlyTx: str("monthly_tx_bytes").flatMap { Int($0) },
            sessionUptime: str("realtime_time").flatMap { Int($0) },
            monthlyUptime: str("monthly_time").flatMap { Int($0) }
        )
    }

    var networkLabel: String {
        switch networkType {
        case "ENDC": return "5G"
        case "": return "—"
        default: return networkType
        }
    }

    var signalQuality: SignalQuality {
        switch signalBars {
        case ...0: return .noSignal
        case 1: return .veryWeak
        case 2: return .weak
        case 3: return .medium
        case 4: return .good
        default: return .veryGood
        }
    }

    var totalBytesForHistory: Int? {
        guard let rx = totalRx, let tx = totalTx else { return nil }
        return rx + tx
    }
}
