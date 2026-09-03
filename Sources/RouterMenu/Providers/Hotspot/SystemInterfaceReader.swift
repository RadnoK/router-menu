import Foundation
import CoreWLAN

/// Reads the live tether interface out of `getifaddrs`.
///
/// `getifaddrs`, not shelling out to `netstat`: same kernel counters, no
/// process spawn on every refresh tick, and no output format to re-parse when
/// macOS changes its columns.
struct SystemInterfaceReader: InterfaceReading {
    /// The Wi-Fi network name we expect the hotspot to carry. Matching happens
    /// upstream in `ModemMatcher`; here it only decides whether the Wi-Fi
    /// interface currently IS the tether, as opposed to a normal network.
    let expectedSSID: String
    let ssidReader: any SSIDReading

    init(expectedSSID: String, ssidReader: any SSIDReading = CoreWLANReader()) {
        self.expectedSSID = expectedSSID
        self.ssidReader = ssidReader
    }

    func now() -> Date { Date() }

    func read() -> InterfaceReading_Result? {
        // Wi-Fi first: a phone tethered over Wi-Fi is the common case, and the
        // SSID is the only evidence that this link is the hotspot rather than
        // any other network the Mac happens to be on.
        let ssid = ssidReader.currentSSID()
        if let ssid, ssid == expectedSSID,
           let counters = Self.counters(for: "en0") {
            return InterfaceReading_Result(rxBytes: counters.rx, txBytes: counters.tx,
                                           ssid: ssid, medium: .wifi)
        }
        // USB and Bluetooth tethers appear as their own interfaces with a
        // running link. They carry no network name to check, so a live
        // interface in the tether's address range is the whole signal.
        for name in Self.tetherInterfaceNames() {
            if let counters = Self.counters(for: name) {
                return InterfaceReading_Result(rxBytes: counters.rx, txBytes: counters.tx,
                                               ssid: nil,
                                               medium: name.hasPrefix("en") ? .usb : .bluetooth)
            }
        }
        return nil
    }

    /// Interfaces that are up, running and hold an address in 172.20.10.0/24 —
    /// the range iOS hands out to tethered clients, and the cheapest reliable
    /// way to tell a phone tether from any other adapter.
    static func tetherInterfaceNames() -> [String] {
        var found: [String] = []
        var head: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&head) == 0, let first = head else { return [] }
        defer { freeifaddrs(head) }

        for ptr in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let flags = Int32(ptr.pointee.ifa_flags)
            guard flags & IFF_UP != 0, flags & IFF_RUNNING != 0,
                  flags & IFF_LOOPBACK == 0,
                  let addr = ptr.pointee.ifa_addr,
                  addr.pointee.sa_family == UInt8(AF_INET) else { continue }

            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            guard getnameinfo(addr, socklen_t(addr.pointee.sa_len),
                              &host, socklen_t(host.count),
                              nil, 0, NI_NUMERICHOST) == 0 else { continue }
            guard String(cString: host).hasPrefix("172.20.10.") else { continue }

            let name = String(cString: ptr.pointee.ifa_name)
            if !found.contains(name) { found.append(name) }
        }
        return found
    }

    /// Cumulative byte counters for one interface, from the kernel's `if_data`.
    static func counters(for interface: String) -> (rx: Int, tx: Int)? {
        var head: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&head) == 0, let first = head else { return nil }
        defer { freeifaddrs(head) }

        for ptr in sequence(first: first, next: { $0.pointee.ifa_next }) {
            guard String(cString: ptr.pointee.ifa_name) == interface,
                  let addr = ptr.pointee.ifa_addr,
                  addr.pointee.sa_family == UInt8(AF_LINK),
                  let raw = ptr.pointee.ifa_data else { continue }
            let data = raw.assumingMemoryBound(to: if_data.self).pointee
            return (rx: Int(data.ifi_ibytes), tx: Int(data.ifi_obytes))
        }
        return nil
    }
}
