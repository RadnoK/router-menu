import Foundation

enum HotspotError: Error {
    /// No tether interface is up — the phone is unplugged or the hotspot off.
    case notTethered
}

/// Reads a tethered phone's link from the Mac's own network interface.
///
/// Unlike every other driver, this one never talks to the device. macOS does
/// not expose an iPhone's battery or its cellular radio to a Mac app — those
/// travel over Continuity, not over the tether — so the fields the phone keeps
/// to itself stay nil rather than being filled with plausible-looking zeroes.
/// What the Mac CAN see is the link: how many bytes crossed it, over which
/// medium, under which network name.
final class HotspotDriver: ModemDriving, @unchecked Sendable {
    private let reader: any InterfaceReading
    /// The previous reading, so a rate can be derived. Cumulative counters
    /// alone say nothing about current speed.
    private var previous: InterfaceSample?

    init(reader: any InterfaceReading) {
        self.reader = reader
    }

    func fetch() async throws -> ModemData {
        guard let reading = reader.read() else { throw HotspotError.notTethered }
        let sample = InterfaceSample(rxBytes: reading.rxBytes,
                                     txBytes: reading.txBytes,
                                     at: reader.now())
        let speed = InterfaceSample.speed(from: previous, to: sample)
        previous = sample

        return ModemData(
            batteryPercent: nil,   // Continuity-only; unreachable from a Mac app
            isCharging: false,
            signalBars: 0,         // the phone's radio, not the tether link
            networkType: reading.medium.label,
            provider: reading.ssid,
            rsrp: nil,
            sinr: nil,
            isOnline: true,
            rxSpeed: speed?.rx,
            txSpeed: speed?.tx,
            sessionRx: nil,
            sessionTx: nil,
            // Since the interface came up, not since the phone was first used
            // — a different meaning from a modem's lifetime counter.
            totalRx: reading.rxBytes,
            totalTx: reading.txBytes,
            monthlyRx: nil,
            monthlyTx: nil,
            sessionUptime: nil,
            monthlyUptime: nil)
    }

    func probe() async -> Bool { reader.read() != nil }
}
