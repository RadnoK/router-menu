import Foundation

enum AppState: Equatable {
    case hidden
    case connected(ModemData)
    case locationDenied
    case error(String)
}
