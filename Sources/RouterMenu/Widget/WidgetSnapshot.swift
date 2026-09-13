import Foundation

/// What the widget process is allowed to know about the modem.
///
/// Deliberately not `ModemData`: this is a cross-process contract written by
/// the app and read by an extension that may be running a *different build*
/// after an update — the app relaunches on install, the widget host does not.
/// A narrow struct with `decodeIfPresent` throughout survives that skew, while
/// sharing the 18-field live model would turn every field change into a
/// widget that renders nothing.
public struct WidgetSnapshot: Codable, Equatable {
    /// When the app last spoke to the modem. The widget renders staleness from
    /// this, so a reading that stopped updating never poses as current.
    public let capturedAt: Date
    /// Device name, so a user with several modems knows which one this is.
    public let deviceName: String
    public let batteryPercent: Int?
    public let isCharging: Bool
    public let signalBars: Int
    public let networkLabel: String
    public let rsrp: Int?
    public let sinr: Double?
    /// Bytes per second at capture time, already differenced by the app —
    /// the widget never sees raw counters and so can't fabricate a spike.
    public let rxSpeed: Int?
    public let txSpeed: Int?
    public let sessionRx: Int?
    public let sessionTx: Int?
    /// Downsampled 24 h battery history for the large widget's chart.
    public let batteryHistory: [Point]
    public let isOnline: Bool

    public struct Point: Codable, Equatable {
        public let t: Date
        public let v: Double

        public init(t: Date, v: Double) {
            self.t = t
            self.v = v
        }
    }

    public init(capturedAt: Date,
         deviceName: String,
         batteryPercent: Int?,
         isCharging: Bool,
         signalBars: Int,
         networkLabel: String,
         rsrp: Int?,
         sinr: Double?,
         rxSpeed: Int?,
         txSpeed: Int?,
         sessionRx: Int?,
         sessionTx: Int?,
         batteryHistory: [Point],
         isOnline: Bool) {
        self.capturedAt = capturedAt
        self.deviceName = deviceName
        self.batteryPercent = batteryPercent
        self.isCharging = isCharging
        self.signalBars = signalBars
        self.networkLabel = networkLabel
        self.rsrp = rsrp
        self.sinr = sinr
        self.rxSpeed = rxSpeed
        self.txSpeed = txSpeed
        self.sessionRx = sessionRx
        self.sessionTx = sessionTx
        self.batteryHistory = batteryHistory
        self.isOnline = isOnline
    }

    /// Every field optional-tolerant: a snapshot written by a newer app must
    /// still decode in an older widget binary rather than blanking the view.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        capturedAt = try c.decodeIfPresent(Date.self, forKey: .capturedAt) ?? .distantPast
        deviceName = try c.decodeIfPresent(String.self, forKey: .deviceName) ?? ""
        batteryPercent = try c.decodeIfPresent(Int.self, forKey: .batteryPercent)
        isCharging = try c.decodeIfPresent(Bool.self, forKey: .isCharging) ?? false
        signalBars = try c.decodeIfPresent(Int.self, forKey: .signalBars) ?? 0
        networkLabel = try c.decodeIfPresent(String.self, forKey: .networkLabel) ?? "—"
        rsrp = try c.decodeIfPresent(Int.self, forKey: .rsrp)
        sinr = try c.decodeIfPresent(Double.self, forKey: .sinr)
        rxSpeed = try c.decodeIfPresent(Int.self, forKey: .rxSpeed)
        txSpeed = try c.decodeIfPresent(Int.self, forKey: .txSpeed)
        sessionRx = try c.decodeIfPresent(Int.self, forKey: .sessionRx)
        sessionTx = try c.decodeIfPresent(Int.self, forKey: .sessionTx)
        batteryHistory = try c.decodeIfPresent([Point].self, forKey: .batteryHistory) ?? []
        isOnline = try c.decodeIfPresent(Bool.self, forKey: .isOnline) ?? false
    }
}
