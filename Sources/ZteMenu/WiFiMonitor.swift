import Foundation
import CoreWLAN

protocol SSIDReading: Sendable {
    func currentSSID() -> String?
}

struct WiFiMonitor: Sendable {
    let targetSSID: String
    let reader: SSIDReading

    init(targetSSID: String = Config.targetSSID, reader: SSIDReading = CoreWLANReader()) {
        self.targetSSID = targetSSID
        self.reader = reader
    }

    var isOnTargetNetwork: Bool {
        reader.currentSSID() == targetSSID
    }
}

struct CoreWLANReader: SSIDReading {
    func currentSSID() -> String? {
        CWWiFiClient.shared().interface()?.ssid()
    }
}
