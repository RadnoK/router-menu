import Foundation

/// Which link the phone is tethered over. The Mac can tell these apart; the
/// phone's own cellular radio behind them is invisible from here.
enum HotspotMedium: Sendable, Equatable {
    case wifi, usb, bluetooth

    /// The label shown in the popover's network row.
    var label: String {
        switch self {
        case .wifi: return "Wi-Fi"
        case .usb: return "USB"
        case .bluetooth: return "Bluetooth"
        }
    }
}

/// One reading of the tether interface: cumulative byte counters plus the
/// identity of the link they belong to.
struct InterfaceReading_Result: Sendable, Equatable {
    let rxBytes: Int
    let txBytes: Int
    /// The hotspot's network name, when the link carries one (Wi-Fi does,
    /// USB and Bluetooth do not).
    let ssid: String?
    let medium: HotspotMedium
}

/// The seam between the driver and `getifaddrs`, so the arithmetic can be
/// tested without a tethered phone attached.
protocol InterfaceReading: Sendable {
    /// The current reading, or nil when no tether interface is up.
    func read() -> InterfaceReading_Result?
    func now() -> Date
}

/// A byte-counter reading pinned to the moment it was taken.
struct InterfaceSample: Sendable, Equatable {
    let rxBytes: Int
    let txBytes: Int
    let at: Date

    init(rxBytes: Int, txBytes: Int, at: Date) {
        self.rxBytes = rxBytes
        self.txBytes = txBytes
        self.at = at
    }

    /// Bytes per second between two samples, or nil when no rate can honestly
    /// be derived — no previous sample, or no time passed between them.
    ///
    /// The kernel's counters are cumulative since the interface came up, so a
    /// LOWER total means the counter restarted (reboot, re-tether, 32-bit
    /// wrap) rather than that traffic ran backwards. That clamps to zero: the
    /// negative delta would otherwise render as an enormous bogus speed.
    static func speed(from previous: InterfaceSample?,
                      to current: InterfaceSample) -> (rx: Int, tx: Int)? {
        guard let previous else { return nil }
        let elapsed = current.at.timeIntervalSince(previous.at)
        guard elapsed > 0 else { return nil }
        let rx = max(0, current.rxBytes - previous.rxBytes)
        let tx = max(0, current.txBytes - previous.txBytes)
        return (rx: Int(Double(rx) / elapsed), tx: Int(Double(tx) / elapsed))
    }
}
