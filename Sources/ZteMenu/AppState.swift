import Foundation

/// Why the modem could not be read. Carrying a case instead of a message keeps
/// the store language-independent and its tests stable.
enum ModemErrorKind: Sendable, Equatable {
    case loginFailed
    case unreachable
}

enum AppState: Equatable {
    case hidden
    case connected(ModemData)
    case locationDenied
    case error(ModemErrorKind)
}
