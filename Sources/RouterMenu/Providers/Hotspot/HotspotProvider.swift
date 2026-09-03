import Foundation

enum HotspotProvider {
    static let descriptor = ProviderDescriptor(
        // Just the device, not the feature: the name rides in a narrow badge
        // in the devices list, and "iPhone Hotspot" wraps to two lines there.
        displayName: "iPhone",
        // Never dialled — the driver reads the Mac's interface, not a device.
        // iOS hands tethered clients 172.20.10.x, so this is the gateway a
        // user would recognise if it is ever surfaced.
        defaultBaseURL: URL(string: "http://172.20.10.1")!,
        defaultSSID: "",
        // No IP probe: nothing listens on the tether gateway, so reachability
        // would answer for a device that has no panel to answer with.
        supportedMatchModes: [.ssid],
        defaultMatchMode: .ssid,
        capabilities: ModemCapabilities(hasBattery: false,
                                        passwordRole: .none,
                                        needsUsername: false,
                                        hasRadioSignal: false,
                                        hasSessionCounters: false),
        makeDriver: { profile, _, _ in
            HotspotDriver(reader: SystemInterfaceReader(expectedSSID: profile.ssid))
        }
    )
}
