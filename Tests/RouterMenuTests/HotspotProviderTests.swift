import XCTest
@testable import RouterMenu

/// The hotspot is the first provider that reads the Mac rather than a device,
/// so its descriptor makes claims the shared UI depends on.
final class HotspotProviderTests: XCTestCase {
    private let d = ProviderCatalog.descriptor(for: .hotspot)

    /// Everything the phone keeps to itself. These flags are what make the
    /// battery and signal sections disappear instead of rendering blanks.
    func testCapabilitiesAdmitWhatTheMacCannotSee() {
        XCTAssertFalse(d.capabilities.hasBattery)
        XCTAssertFalse(d.capabilities.hasRadioSignal)
        XCTAssertFalse(d.capabilities.hasSessionCounters)
        XCTAssertEqual(d.capabilities.passwordRole, .none, "a tether has no panel to log into")
        XCTAssertFalse(d.capabilities.needsUsername)
    }

    /// An IP probe would need something listening on the tether gateway, and
    /// nothing does. Recognition goes by network name.
    func testOnlySSIDMatchingIsOffered() {
        XCTAssertEqual(d.supportedMatchModes, [.ssid])
        XCTAssertEqual(d.defaultMatchMode, .ssid)
    }

    func testAFreshProfileInheritsSSIDMatching() {
        let profile = ModemProfile.makeDefault(provider: .hotspot)
        XCTAssertEqual(profile.provider, .hotspot)
        XCTAssertEqual(profile.matchMode, .ssid)
    }

    /// The raw value is persisted inside stored profiles.
    func testTheRawValueIsStable() {
        XCTAssertEqual(ProviderKind.hotspot.rawValue, "hotspot")
    }

    func testEveryProviderKindHasADescriptor() {
        for kind in ProviderKind.allCases {
            XCTAssertFalse(ProviderCatalog.descriptor(for: kind).displayName.isEmpty,
                           "\(kind) is missing a descriptor")
        }
    }
}

/// A hotspot has no factory SSID to fall back on, so a fresh profile takes the
/// name of the network the Mac is currently on.
extension HotspotProviderTests {
    func testAFreshHotspotProfileAdoptsTheCurrentNetworkName() {
        let profile = ModemProfile.makeDefault(provider: .hotspot,
                                               currentSSID: "iPhone (Konrad)")
        XCTAssertEqual(profile.ssid, "iPhone (Konrad)")
    }

    func testAFreshHotspotProfileToleratesBeingOffline() {
        let profile = ModemProfile.makeDefault(provider: .hotspot, currentSSID: nil)
        XCTAssertEqual(profile.ssid, "", "the user fills it in; no invented name")
    }

    /// Providers that ship a real factory SSID must keep it — the live network
    /// name is a fallback for those that cannot have one, not an override.
    func testAProviderWithAFactorySSIDIgnoresTheCurrentNetwork() {
        let profile = ModemProfile.makeDefault(provider: .zte,
                                               currentSSID: "iPhone (Konrad)")
        XCTAssertEqual(profile.ssid, "ZTE_B4B622")
    }
}

/// The transfer row's meaning changes with the provider, so the key it renders
/// has to change with it.
extension HotspotProviderTests {
    @MainActor
    func testBothTransferLabelsAreTranslated() throws {
        let resources = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // RouterMenuTests
            .deletingLastPathComponent()   // Tests
            .deletingLastPathComponent()   // repo root
            .appendingPathComponent("Resources")
        // The bundle is the directory CONTAINING the .lproj folders — pointing
        // at an .lproj itself finds no strings table at all.
        let bundle = try XCTUnwrap(Bundle(path: resources.path))
        for language in [AppLanguage.en, .pl] {
            let l10n = L10n(language: language, bundles: [bundle])
            for key in [LocKey.popoverSinceConnected, .popoverTotal] {
                XCTAssertNotEqual(l10n(key), key.rawValue,
                                  "\(key.rawValue) is untranslated in \(language.rawValue)")
            }
        }
    }
}
