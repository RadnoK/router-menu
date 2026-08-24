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
}
