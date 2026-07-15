import Foundation

public protocol ReachabilityChecking: Sendable {
    func isReachable(_ url: URL) async -> Bool
}

public struct NetworkDetector: Sendable {
    let reader: SSIDReading
    let reachability: ReachabilityChecking

    public init(reader: SSIDReading = CoreWLANReader(),
                reachability: ReachabilityChecking = URLReachability()) {
        self.reader = reader
        self.reachability = reachability
    }

    func isOnTarget(mode: NetworkMode, ssid: String, modemURL: URL) async -> Bool {
        switch mode {
        case .bySSID:
            return reader.currentSSID() == ssid
        case .byIPReachable:
            return await reachability.isReachable(modemURL)
        }
    }
}

public struct URLReachability: ReachabilityChecking {
    public init() {}
    public func isReachable(_ url: URL) async -> Bool {
        var req = URLRequest(url: url)
        req.timeoutInterval = 3
        req.httpMethod = "HEAD"
        do {
            _ = try await URLSession.shared.data(for: req, delegate: nil)
            return true
        } catch {
            return false
        }
    }
}
