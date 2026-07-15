import Foundation
import CoreWLAN

public protocol SSIDReading: Sendable {
    func currentSSID() -> String?
}

public struct WiFiMonitor: Sendable {
    let targetSSID: String
    let reader: SSIDReading

    public init(targetSSID: String = Config.targetSSID, reader: SSIDReading = CoreWLANReader()) {
        self.targetSSID = targetSSID
        self.reader = reader
    }

    var isOnTargetNetwork: Bool {
        reader.currentSSID() == targetSSID
    }
}

public struct CoreWLANReader: SSIDReading {
    public init() {}

    public func currentSSID() -> String? {
        CWWiFiClient.shared().interface()?.ssid()
    }
}
