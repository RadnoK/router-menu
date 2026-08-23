# Provider-Based Modem Architecture Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Decouple the app from the ZTE U50 behind a provider abstraction (identity enum + descriptor + driver protocol), store the configuration as a list of device profiles with per-device "contextual" settings, and drive detection through a profile matcher — so a future provider (e.g. Asus) is one folder plus one enum case.

**Architecture:** A `ProviderKind` enum identifies device families; `ProviderCatalog` maps each to a `ProviderDescriptor` (display name, defaults, supported match modes, capabilities, driver factory). The user's device is a `ModemProfile` (provider + match rule + address + battery/stat preferences) stored in `AppSettings.profiles`. `ModemMatcher` finds the first matching profile (SSID compare or driver probe); `ModemStore` fetches through the matched profile's driver. Battery UI and alerts are gated on the provider's `hasBattery` capability and read per-profile settings.

**Tech Stack:** Swift 6, SwiftUI, SwiftPM (no Xcode project), XCTest, CoreWLAN, Observation, Security (Keychain).

**Spec:** `docs/superpowers/specs/2026-08-23-modem-providers-design.md`

## Global Constraints

- Work directly on `main` — this repo uses no feature branches (user preference). Another session may be committing in parallel: **never reset or rewrite history**, only append commits; run `git pull --rebase=false` is unnecessary (no remote flow) but re-check `git log` before each commit.
- Commits, code, comments, and docs are **English**. Commit style: `type(scope): summary` (see `git log`).
- TDD: every task starts with a failing test, ends with the full suite green. Baseline at plan time is **119 tests, 0 failures**. A parallel session may add tests of its own, so verify DELTAS (this task's new tests all pass, nothing that passed before fails), not absolute totals.
- Run `swift test` (full suite) before every commit. `swift test --filter <Class>` for the tight loop.
- ZTE driver behaviour is frozen: the golden request assertions (URLs, query fields, `Referer` header, LD/SHA256 login sequence) from today's `ModemClientTests` must keep passing unchanged through every rename.
- The persisted settings key stays `"zte.settings"`; the Keychain service/account (`io.8lines.zte-menu` / `"modem"`) stays single-slot. No app/bundle renaming.
- New domain types are **internal** (tests use `@testable import ZteMenu`). Existing `public` markers stay where they are, except `ModemStore.init`, which becomes internal in Task 1 because its factory parameter gains an internal type (its only callers are in-module and tests).
- Brand names (`ZTE`, future `Asus`) are never localized; every other new user-facing string gets a `LocKey` case plus `en` and `pl` entries.
- `BatteryNotificationSettings`, `StatVisibility`, `BatteryThreshold`, `BatteryAlertDecider` keep their current shapes — this plan moves where they live/are read from, not what they do.

## File Map (end state)

```
Sources/ZteMenu/Modem/
  ModemData.swift        moved from Sources/ZteMenu/, parse(_:) removed
  ModemDriving.swift     NEW: driver protocol
  ModemProfile.swift     NEW: MatchMode + ModemProfile (+ adopting(provider:))
  Provider.swift         NEW: ProviderKind, PasswordRole, ModemCapabilities,
                         ProviderDescriptor, ProviderCatalog
  ModemMatcher.swift     NEW: SSIDReading, CoreWLANReader, MatchResult, ModemMatcher
Sources/ZteMenu/Providers/ZTE/
  ZTEProvider.swift      NEW: the ZTE descriptor
  ZTEClient.swift        moved+renamed from ModemClient.swift, + parse + probe
  ZTEAuth.swift          moved from Sources/ZteMenu/
DELETED: WiFiMonitor.swift, NetworkDetector.swift,
         Tests/.../WiFiMonitorTests.swift, Tests/.../NetworkDetectorTests.swift,
         Tests/.../ModemDataTests.swift (content moves to ZTEClientParseTests)
```

---

### Task 1: Extract the ZTE driver behind a `ModemDriving` protocol

Pure extraction — no behaviour change except the new `probe()` method. The app compiles and behaves identically afterwards.

**Files:**
- Create: `Sources/ZteMenu/Modem/ModemDriving.swift`
- Move: `Sources/ZteMenu/ModemClient.swift` → `Sources/ZteMenu/Providers/ZTE/ZTEClient.swift` (struct renamed `ModemClient` → `ZTEClient`)
- Move: `Sources/ZteMenu/ZTEAuth.swift` → `Sources/ZteMenu/Providers/ZTE/ZTEAuth.swift` (content unchanged)
- Move: `Sources/ZteMenu/ModemData.swift` → `Sources/ZteMenu/Modem/ModemData.swift` (remove `static func parse`)
- Modify: `Sources/ZteMenu/ModemStore.swift` (factory type only)
- Move: `Tests/ZteMenuTests/ModemClientTests.swift` → `Tests/ZteMenuTests/ZTEClientTests.swift`
- Create: `Tests/ZteMenuTests/ZTEClientParseTests.swift` (from `ModemDataTests.swift`, which is deleted)

**Interfaces:**
- Produces: `protocol ModemDriving: Sendable { func fetch() async throws -> ModemData; func probe() async -> Bool }`; `struct ZTEClient: ModemDriving` with `init(baseURL: URL = Config.modemBaseURL, http: HTTPFetching = URLSession.shared, password: String? = nil)` and `static func parse(_ raw: [String: String]) -> ModemData`; `ModemStore.init`'s factory parameter becomes `clientFactory: @escaping @MainActor (URL, String?) -> any ModemDriving`.
- Consumes: existing `ModemData`, `HTTPFetching`, `Config`, `ZTEAuth`.

- [ ] **Step 1: Write the failing probe tests** — append to the (still-named) `Tests/ZteMenuTests/ModemClientTests.swift`:

```swift
final class ZTEClientProbeTests: XCTestCase {
    func testProbeSucceedsWhenTheDeviceAnswers() async throws {
        let stub = StubHTTP(payload: Data("<html>".utf8))
        let client = ZTEClient(baseURL: Config.modemBaseURL, http: stub)

        let reachable = await client.probe()

        XCTAssertTrue(reachable)
        let request = try XCTUnwrap(stub.capturedRequest.request)
        XCTAssertEqual(request.httpMethod, "HEAD")
        XCTAssertEqual(request.url?.absoluteString, "http://192.168.0.1")
        XCTAssertEqual(request.timeoutInterval, 3)
    }

    func testProbeFailsWhenTheRequestThrows() async {
        struct Boom: Error {}
        struct ThrowingHTTP: HTTPFetching {
            func data(for request: URLRequest) async throws -> Data { throw Boom() }
        }
        let client = ZTEClient(baseURL: Config.modemBaseURL, http: ThrowingHTTP())
        let reachable = await client.probe()
        XCTAssertFalse(reachable)
    }
}
```

- [ ] **Step 2: Run to verify failure**

Run: `swift test --filter ZTEClientProbeTests 2>&1 | tail -20`
Expected: COMPILE ERROR — `cannot find 'ZTEClient' in scope`.

- [ ] **Step 3: Create the protocol file** — `Sources/ZteMenu/Modem/ModemDriving.swift`:

```swift
import Foundation

/// A modem/router protocol driver. One implementation per provider; the rest
/// of the app talks to a device only through this seam.
protocol ModemDriving: Sendable {
    /// Read the device's current state.
    func fetch() async throws -> ModemData
    /// Whether THIS provider's device answers at the configured address.
    /// Used by IP-probe matching. Plain reachability is an acceptable v1;
    /// a provider can later strengthen it to a protocol-level fingerprint.
    func probe() async -> Bool
}
```

- [ ] **Step 4: Move and rename the client**

```bash
mkdir -p Sources/ZteMenu/Providers/ZTE Sources/ZteMenu/Modem
git mv Sources/ZteMenu/ModemClient.swift Sources/ZteMenu/Providers/ZTE/ZTEClient.swift
git mv Sources/ZteMenu/ZTEAuth.swift Sources/ZteMenu/Providers/ZTE/ZTEAuth.swift
git mv Sources/ZteMenu/ModemData.swift Sources/ZteMenu/Modem/ModemData.swift
git mv Tests/ZteMenuTests/ModemClientTests.swift Tests/ZteMenuTests/ZTEClientTests.swift
```

In `ZTEClient.swift`: rename `public struct ModemClient` → `public struct ZTEClient: ModemDriving`, keep everything else (`statusFields`, `trafficFields`, `fetch`, `login`, `getCmd`, the `HTTPFetching` extension on `URLSession`, `ModemError`), and append inside the struct:

```swift
    /// v1 probe: plain reachability. A HEAD against the panel with the same
    /// 3-second budget the old `URLReachability` used.
    func probe() async -> Bool {
        var request = URLRequest(url: baseURL)
        request.httpMethod = "HEAD"
        request.timeoutInterval = 3
        return (try? await http.data(for: request)) != nil
    }
```

Move `ModemData.parse` (the whole `static func parse(_ raw: [String: String]) -> ModemData` including its inner `str` helper) out of `Modem/ModemData.swift` into `ZTEClient.swift` as an extension — it is a ZTE field mapping, not a model concern:

```swift
extension ZTEClient {
    /// Maps the modem's goform key/value response onto the neutral model.
    /// Empty strings mean "field absent" on this firmware.
    static func parse(_ raw: [String: String]) -> ModemData {
        func str(_ key: String) -> String? {
            guard let v = raw[key], !v.isEmpty else { return nil }
            return v
        }
        return ModemData(
            batteryPercent: str("battery_value").flatMap { Int($0) },
            isCharging: raw["battery_charging"] == "1",
            signalBars: str("signalbar").flatMap { Int($0) } ?? 0,
            networkType: str("network_type") ?? "",
            provider: str("network_provider"),
            rsrp: str("Z5g_rsrp").flatMap { Int($0) },
            sinr: str("Z5g_SINR").flatMap { Double($0) },
            isOnline: raw["ppp_status"] == "ppp_connected",
            rxSpeed: str("realtime_rx_thrpt").flatMap { Int($0) },
            txSpeed: str("realtime_tx_thrpt").flatMap { Int($0) },
            sessionRx: str("realtime_rx_bytes").flatMap { Int($0) },
            sessionTx: str("realtime_tx_bytes").flatMap { Int($0) },
            totalRx: str("total_rx_bytes").flatMap { Int($0) },
            totalTx: str("total_tx_bytes").flatMap { Int($0) },
            monthlyRx: str("monthly_rx_bytes").flatMap { Int($0) },
            monthlyTx: str("monthly_tx_bytes").flatMap { Int($0) },
            sessionUptime: str("realtime_time").flatMap { Int($0) },
            monthlyUptime: str("monthly_time").flatMap { Int($0) }
        )
    }
}
```

(This is today's `ModemData.parse` body unchanged — cut it from `Modem/ModemData.swift` rather than retyping, then verify it matches the above.)

Update the one call site in `fetch()`: `return ModemData.parse(raw)` → `return Self.parse(raw)`.

- [ ] **Step 5: Point `ModemStore` at the protocol** — in `Sources/ZteMenu/ModemStore.swift` change only the factory's type (three places: the stored property, the `init` parameter, the default value):

```swift
    private let clientFactory: @MainActor (URL, String?) -> any ModemDriving
    // in init:
                clientFactory: @escaping @MainActor (URL, String?) -> any ModemDriving = { url, pass in
                    ZTEClient(baseURL: url, http: SessionHTTP(), password: pass)
                }
```

Because `ModemDriving` and (after later tasks) profile types are internal, drop `public` from this `init` — its callers are `AppDelegate` (same module) and `@testable` tests.

- [ ] **Step 6: Migrate the tests** — in `Tests/ZteMenuTests/ZTEClientTests.swift` rename classes `ModemClientTests` → `ZTEClientTests`, `ModemClientLoginTests` → `ZTEClientLoginTests`, and every `ModemClient(` → `ZTEClient(`. Assertions stay byte-for-byte (they are the golden behaviour guard). Create `Tests/ZteMenuTests/ZTEClientParseTests.swift` as a copy of `ModemDataTests.swift` with the class renamed `ModemDataTests` → `ZTEClientParseTests` and every `ModemData.parse(` → `ZTEClient.parse(`; then `git rm Tests/ZteMenuTests/ModemDataTests.swift`. In `Tests/ZteMenuTests/ModemStoreTests.swift`, update the factory stub's type:

```swift
        let factory: @MainActor (URL, String?) -> any ModemDriving = { url, pass in
            let http: any HTTPFetching = throwing != nil ? ThrowingHTTP(error: throwing!) : SequenceHTTP([json])
            return ZTEClient(baseURL: url, http: http, password: pass)
        }
```

- [ ] **Step 7: Run the full suite**

Run: `swift test 2>&1 | tail -3`
Expected: PASS, 0 failures — delta vs the previous run: +2 (the probe tests); every migrated golden test still green.

- [ ] **Step 8: Commit**

```bash
git add -A && git commit -m "refactor(modem): extract the ZTE driver behind a ModemDriving protocol"
```

---

### Task 2: Provider identity, capabilities, descriptor, catalog

**Files:**
- Create: `Sources/ZteMenu/Modem/Provider.swift`
- Create: `Sources/ZteMenu/Modem/ModemProfile.swift` (only `MatchMode` for now; the profile struct arrives in Task 3)
- Create: `Sources/ZteMenu/Providers/ZTE/ZTEProvider.swift`
- Test: `Tests/ZteMenuTests/ProviderCatalogTests.swift`

**Interfaces:**
- Produces: `enum ProviderKind: String, Codable, CaseIterable, Sendable { case zte }`; `enum PasswordRole { case none, unlocksTraffic, requiredForAll }`; `struct ModemCapabilities { let hasBattery: Bool; let passwordRole: PasswordRole }`; `struct ProviderDescriptor` with `displayName: String`, `defaultBaseURL: URL`, `defaultSSID: String`, `supportedMatchModes: [MatchMode]`, `defaultMatchMode: MatchMode`, `capabilities: ModemCapabilities`, `makeDriver: @Sendable (URL, String?, any HTTPFetching) -> any ModemDriving`; `ProviderCatalog.descriptor(for: ProviderKind) -> ProviderDescriptor`; `enum MatchMode: String, Codable, CaseIterable, Sendable { case ssid, ipProbe }`.
- Consumes: `ModemDriving`, `ZTEClient`, `HTTPFetching` (Task 1).

- [ ] **Step 1: Write the failing tests** — `Tests/ZteMenuTests/ProviderCatalogTests.swift`:

```swift
import XCTest
@testable import ZteMenu

/// Every provider the enum names must be fully described — these are the
/// compile-time-adjacent guarantees the architecture's "one folder + one
/// case" promise rests on.
final class ProviderCatalogTests: XCTestCase {
    func testEveryProviderHasACoherentDescriptor() {
        for kind in ProviderKind.allCases {
            let d = ProviderCatalog.descriptor(for: kind)
            XCTAssertFalse(d.displayName.isEmpty, "\(kind) has no display name")
            XCTAssertFalse(d.supportedMatchModes.isEmpty, "\(kind) supports no match mode")
            XCTAssertTrue(d.supportedMatchModes.contains(d.defaultMatchMode),
                          "\(kind)'s default match mode is not among its supported modes")
            XCTAssertFalse(d.defaultSSID.isEmpty, "\(kind) has no default SSID")
        }
    }

    func testZTEDescriptorMatchesTheU50() {
        let d = ProviderCatalog.descriptor(for: .zte)
        XCTAssertEqual(d.displayName, "ZTE")
        XCTAssertEqual(d.defaultBaseURL.absoluteString, "http://192.168.0.1")
        XCTAssertEqual(d.defaultSSID, "ZTE_B4B622")
        XCTAssertEqual(d.supportedMatchModes, [.ssid, .ipProbe])
        XCTAssertEqual(d.defaultMatchMode, .ssid)
        XCTAssertTrue(d.capabilities.hasBattery)
        XCTAssertEqual(d.capabilities.passwordRole, .unlocksTraffic)
    }

    func testZTEFactoryBuildsAZTEDriver() {
        let d = ProviderCatalog.descriptor(for: .zte)
        let driver = d.makeDriver(URL(string: "http://10.0.0.1")!, "secret", URLSession.shared)
        XCTAssertTrue(driver is ZTEClient)
    }

    func testMatchModeRawValuesAreStable() {
        // Persisted in profiles — renaming a case is a settings migration.
        XCTAssertEqual(MatchMode.ssid.rawValue, "ssid")
        XCTAssertEqual(MatchMode.ipProbe.rawValue, "ipProbe")
    }
}
```

- [ ] **Step 2: Run to verify failure**

Run: `swift test --filter ProviderCatalogTests 2>&1 | tail -5`
Expected: COMPILE ERROR — `cannot find 'ProviderKind' in scope`.

- [ ] **Step 3: Implement** — `Sources/ZteMenu/Modem/ModemProfile.swift`:

```swift
import Foundation

/// How a profile recognises that its device is nearby.
/// Raw values are persisted inside profiles — do not rename cases.
enum MatchMode: String, Codable, CaseIterable, Sendable {
    /// Compare the current Wi-Fi network name (needs location permission).
    case ssid
    /// Ask the provider's driver whether the device answers at the address.
    case ipProbe
}
```

`Sources/ZteMenu/Modem/Provider.swift`:

```swift
import Foundation

/// Which device family a profile talks to. Raw values are persisted.
enum ProviderKind: String, Codable, CaseIterable, Sendable {
    case zte
}

/// What the panel password unlocks on a device, so credential UI can be
/// described without knowing the brand.
enum PasswordRole: Sendable, Equatable {
    case none
    /// Status is public; the transfer counters need a login (ZTE U50).
    case unlocksTraffic
    case requiredForAll
}

/// Facts about a device family — facts, not preferences. A router without a
/// battery has no battery UI to configure.
struct ModemCapabilities: Sendable, Equatable {
    let hasBattery: Bool
    let passwordRole: PasswordRole
}

/// How a provider describes itself: identity for the UI, defaults for fresh
/// profiles, capability gates, and the factory producing its driver.
struct ProviderDescriptor: Sendable {
    let displayName: String
    let defaultBaseURL: URL
    let defaultSSID: String
    let supportedMatchModes: [MatchMode]
    let defaultMatchMode: MatchMode
    let capabilities: ModemCapabilities
    let makeDriver: @Sendable (_ baseURL: URL, _ password: String?, _ http: any HTTPFetching) -> any ModemDriving
}

enum ProviderCatalog {
    /// An exhaustive switch on purpose: adding a `ProviderKind` case without
    /// wiring its descriptor is a compile error here, not a runtime miss.
    static func descriptor(for kind: ProviderKind) -> ProviderDescriptor {
        switch kind {
        case .zte: return ZTEProvider.descriptor
        }
    }
}
```

`Sources/ZteMenu/Providers/ZTE/ZTEProvider.swift`:

```swift
import Foundation

enum ZTEProvider {
    static let descriptor = ProviderDescriptor(
        displayName: "ZTE",
        defaultBaseURL: URL(string: "http://192.168.0.1")!,
        defaultSSID: "ZTE_B4B622",
        supportedMatchModes: [.ssid, .ipProbe],
        defaultMatchMode: .ssid,
        capabilities: ModemCapabilities(hasBattery: true, passwordRole: .unlocksTraffic),
        makeDriver: { baseURL, password, http in
            ZTEClient(baseURL: baseURL, http: http, password: password)
        }
    )
}
```

- [ ] **Step 4: Run the full suite**

Run: `swift test 2>&1 | tail -3`
Expected: PASS, 0 failures — delta: +4 (the catalog tests).

- [ ] **Step 5: Commit**

```bash
git add -A && git commit -m "feat(modem): provider catalog with capabilities and descriptors"
```

---

### Task 3: `ModemProfile` — one configured device

**Files:**
- Modify: `Sources/ZteMenu/Modem/ModemProfile.swift`
- Test: `Tests/ZteMenuTests/ModemProfileTests.swift`

**Interfaces:**
- Produces: `struct ModemProfile: Codable, Equatable, Identifiable, Sendable` with `id: UUID`, `provider: ProviderKind`, `matchMode: MatchMode`, `ssid: String`, `modemIP: String`, `showBatteryPercent: Bool`, `batteryNotifications: BatteryNotificationSettings`, `stats: StatVisibility`; `ModemProfile.makeDefault(provider:) -> ModemProfile`; `profile.baseURL: URL`.
- Consumes: `ProviderKind`, `MatchMode`, `ProviderCatalog` (Task 2); `BatteryNotificationSettings`, `StatVisibility` (existing, in `AppSettings.swift`).

- [ ] **Step 1: Write the failing tests** — `Tests/ZteMenuTests/ModemProfileTests.swift`:

```swift
import XCTest
@testable import ZteMenu

final class ModemProfileTests: XCTestCase {
    func testMakeDefaultPrefillsFromTheDescriptor() {
        let p = ModemProfile.makeDefault(provider: .zte)
        XCTAssertEqual(p.provider, .zte)
        XCTAssertEqual(p.matchMode, .ssid)
        XCTAssertEqual(p.ssid, "ZTE_B4B622")
        XCTAssertEqual(p.modemIP, "192.168.0.1")
        XCTAssertFalse(p.showBatteryPercent)
        XCTAssertEqual(p.batteryNotifications, BatteryNotificationSettings())
        XCTAssertEqual(p.stats, StatVisibility())
    }

    func testBaseURLDerivesFromTheIP() {
        var p = ModemProfile.makeDefault(provider: .zte)
        p.modemIP = "10.0.0.138"
        XCTAssertEqual(p.baseURL.absoluteString, "http://10.0.0.138")
    }

    func testUnparsableIPFallsBackToTheProviderDefault() {
        var p = ModemProfile.makeDefault(provider: .zte)
        p.modemIP = "not a host"
        XCTAssertEqual(p.baseURL.absoluteString, "http://192.168.0.1")
    }

    func testRoundTripsThroughCodable() throws {
        var p = ModemProfile.makeDefault(provider: .zte)
        p.matchMode = .ipProbe
        p.showBatteryPercent = true
        p.batteryNotifications.addThreshold(percent: 35, isUrgent: true)
        let decoded = try JSONDecoder().decode(ModemProfile.self,
                                               from: try JSONEncoder().encode(p))
        XCTAssertEqual(decoded, p)
        XCTAssertEqual(decoded.id, p.id, "identity must survive persistence")
    }

    func testDecodesAnEmptyObjectToUsableDefaults() throws {
        // Forgiving decode, the house style: a future field addition must not
        // reset the user's whole configuration.
        let p = try JSONDecoder().decode(ModemProfile.self, from: Data("{}".utf8))
        XCTAssertEqual(p.provider, .zte)
        XCTAssertEqual(p.matchMode, .ssid)
    }
}
```

- [ ] **Step 2: Run to verify failure**

Run: `swift test --filter ModemProfileTests 2>&1 | tail -5`
Expected: COMPILE ERROR — `type 'ModemProfile' has no member 'makeDefault'` / not found.

- [ ] **Step 3: Implement** — append to `Sources/ZteMenu/Modem/ModemProfile.swift`:

```swift
/// One configured device: which provider drives it, how to recognise being
/// near it, where it lives — and how the user wants THIS device presented.
/// Battery and stat preferences are per-profile ("contextual"): a mains-powered
/// router simply has none of them.
struct ModemProfile: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    var provider: ProviderKind
    var matchMode: MatchMode
    /// Used by `.ssid` matching.
    var ssid: String
    /// The driver's address, and the `.ipProbe` target.
    var modemIP: String
    var showBatteryPercent: Bool
    var batteryNotifications: BatteryNotificationSettings
    var stats: StatVisibility

    init(id: UUID = UUID(),
         provider: ProviderKind,
         matchMode: MatchMode,
         ssid: String,
         modemIP: String,
         showBatteryPercent: Bool = false,
         batteryNotifications: BatteryNotificationSettings = BatteryNotificationSettings(),
         stats: StatVisibility = StatVisibility()) {
        self.id = id
        self.provider = provider
        self.matchMode = matchMode
        self.ssid = ssid
        self.modemIP = modemIP
        self.showBatteryPercent = showBatteryPercent
        self.batteryNotifications = batteryNotifications
        self.stats = stats
    }

    /// A fresh profile for a provider, prefilled from its descriptor.
    static func makeDefault(provider: ProviderKind) -> ModemProfile {
        let d = ProviderCatalog.descriptor(for: provider)
        return ModemProfile(provider: provider,
                            matchMode: d.defaultMatchMode,
                            ssid: d.defaultSSID,
                            modemIP: d.defaultBaseURL.host ?? "192.168.0.1")
    }

    var baseURL: URL {
        guard let url = URL(string: "http://\(modemIP)"), url.host != nil else {
            return ProviderCatalog.descriptor(for: provider).defaultBaseURL
        }
        return url
    }

    /// Field-by-field forgiving decode, same style as `AppSettings`: an
    /// unknown or missing key falls to its default instead of throwing away
    /// the user's whole configuration.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        provider = try c.decodeIfPresent(ProviderKind.self, forKey: .provider) ?? .zte
        matchMode = try c.decodeIfPresent(MatchMode.self, forKey: .matchMode) ?? .ssid
        ssid = try c.decodeIfPresent(String.self, forKey: .ssid) ?? ""
        modemIP = try c.decodeIfPresent(String.self, forKey: .modemIP) ?? "192.168.0.1"
        showBatteryPercent = try c.decodeIfPresent(Bool.self, forKey: .showBatteryPercent) ?? false
        batteryNotifications = try c.decodeIfPresent(BatteryNotificationSettings.self,
                                                     forKey: .batteryNotifications)
            ?? BatteryNotificationSettings()
        stats = try c.decodeIfPresent(StatVisibility.self, forKey: .stats) ?? StatVisibility()
    }
}
```

Note: `URL(string: "http://not a host")` is `nil` on modern Foundation, but the extra `url.host != nil` guard keeps the fallback honest if Foundation ever gets more lenient.

- [ ] **Step 4: Run the full suite**

Run: `swift test 2>&1 | tail -3`
Expected: PASS, 0 failures — delta: +5 (the profile tests).

- [ ] **Step 5: Commit**

```bash
git add -A && git commit -m "feat(modem): device profile model with per-device presentation settings"
```

---

### Task 4: `AppSettings` v2 — profile list, lossless migration, transitional accessors

The schema flips to `profiles: [ModemProfile]`. So that this task stays green without touching every view, the old flat names survive as computed accessors forwarding to `profiles[0]`; Task 9 deletes them.

**Files:**
- Modify: `Sources/ZteMenu/AppSettings.swift`
- Modify: `Sources/ZteMenu/SettingsStore.swift`
- Test: `Tests/ZteMenuTests/AppSettingsMigrationTests.swift` (new)
- Modify: `Tests/ZteMenuTests/SettingsStoreTests.swift` (only if a test breaks — the accessors should keep all of them passing)

**Interfaces:**
- Produces: `AppSettings { var profiles: [ModemProfile]; var refreshInterval: TimeInterval; var language: AppLanguage; var showWhenDisconnected: Bool }` (never-empty `profiles` invariant); transitional computed `networkMode/ssid/modemIP/stats/showBatteryPercent/batteryNotifications` forwarding to `profiles[0]` (removed in Task 9); `SettingsStore.profile: ModemProfile { get set }`; `SettingsStore` saves once after loading, so a migrated profile's `id` is stable across launches.
- Consumes: `ModemProfile`, `MatchMode` (Task 3). `NetworkMode` stays alive only to type the transitional accessor.

- [ ] **Step 1: Write the failing tests** — `Tests/ZteMenuTests/AppSettingsMigrationTests.swift`:

```swift
import XCTest
@testable import ZteMenu

@MainActor
final class AppSettingsMigrationTests: XCTestCase {
    private func freshDefaults() -> UserDefaults {
        UserDefaults(suiteName: "mig-\(UUID().uuidString)")!
    }

    /// The exact shape a 0.4.x install has on disk.
    private let legacyPayload = #"""
    {"networkMode":"byIPReachable","ssid":"MyZTE","modemIP":"10.0.0.1",
     "refreshInterval":30,
     "stats":{"basic":false,"radio":true,"transfer":true,"uptime":true},
     "language":"pl","showBatteryPercent":true,"showWhenDisconnected":true,
     "batteryNotifications":{"thresholds":[{"id":"11111111-1111-1111-1111-111111111111",
       "percent":35,"isUrgent":true,"isEnabled":true}],"fullEnabled":true}}
    """#

    func testLegacyFlatPayloadBecomesOneZTEProfile() {
        let d = freshDefaults()
        d.set(Data(legacyPayload.utf8), forKey: "zte.settings")

        let s = SettingsStore(defaults: d).settings

        XCTAssertEqual(s.profiles.count, 1)
        let p = s.profiles[0]
        XCTAssertEqual(p.provider, .zte)
        XCTAssertEqual(p.matchMode, .ipProbe, "legacy byIPReachable maps to ipProbe")
        XCTAssertEqual(p.ssid, "MyZTE")
        XCTAssertEqual(p.modemIP, "10.0.0.1")
        XCTAssertTrue(p.showBatteryPercent)
        XCTAssertFalse(p.stats.basic)
        XCTAssertEqual(p.batteryNotifications.thresholds.map(\.percent), [35])
        XCTAssertTrue(p.batteryNotifications.fullEnabled)
        // App-scoped values stay app-scoped.
        XCTAssertEqual(s.refreshInterval, 30)
        XCTAssertEqual(s.language, .pl)
        XCTAssertTrue(s.showWhenDisconnected)
    }

    func testLegacyBySSIDMapsToSSIDMode() {
        let d = freshDefaults()
        d.set(Data(#"{"networkMode":"bySSID","ssid":"X"}"#.utf8), forKey: "zte.settings")
        XCTAssertEqual(SettingsStore(defaults: d).settings.profiles[0].matchMode, .ssid)
    }

    func testEmptyProfilesArrayIsRepaired() {
        let d = freshDefaults()
        d.set(Data(#"{"profiles":[]}"#.utf8), forKey: "zte.settings")
        let s = SettingsStore(defaults: d).settings
        XCTAssertEqual(s.profiles.count, 1, "the never-empty invariant holds")
        XCTAssertEqual(s.profiles[0].provider, .zte)
    }

    func testEncodingWritesOnlyTheNewSchema() throws {
        let data = try JSONEncoder().encode(AppSettings())
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertNotNil(object["profiles"])
        for legacyKey in ["networkMode", "ssid", "modemIP", "stats",
                          "showBatteryPercent", "batteryNotifications"] {
            XCTAssertNil(object[legacyKey], "legacy key \(legacyKey) must not be written back")
        }
    }

    func testMigratedProfileIdIsStableAcrossLaunches() {
        let d = freshDefaults()
        d.set(Data(legacyPayload.utf8), forKey: "zte.settings")
        let first = SettingsStore(defaults: d).settings.profiles[0].id
        let second = SettingsStore(defaults: d).settings.profiles[0].id
        XCTAssertEqual(first, second,
                       "the store must persist the migrated schema immediately")
    }

    func testProfileAccessorEditsTheFirstProfile() {
        let store = SettingsStore(defaults: freshDefaults())
        store.profile.ssid = "Edited"
        XCTAssertEqual(store.settings.profiles[0].ssid, "Edited")
    }
}
```

- [ ] **Step 2: Run to verify failure**

Run: `swift test --filter AppSettingsMigrationTests 2>&1 | tail -5`
Expected: COMPILE ERROR — `value of type 'AppSettings' has no member 'profiles'`.

- [ ] **Step 3: Rewrite `AppSettings`** — in `Sources/ZteMenu/AppSettings.swift`, keep `NetworkMode`, `StatVisibility`, `BatteryThreshold`, `BatteryNotificationSettings` untouched, and replace the `AppSettings` struct with:

```swift
struct AppSettings: Codable, Equatable {
    /// The user's configured devices, first match wins. Never empty — v1's UI
    /// edits exactly `profiles[0]`.
    var profiles: [ModemProfile] = [.makeDefault(provider: .zte)]
    var refreshInterval: TimeInterval = Config.refreshInterval
    var language: AppLanguage = .system
    var showWhenDisconnected: Bool = false

    static let defaults = AppSettings()

    enum CodingKeys: String, CodingKey {
        case profiles, refreshInterval, language, showWhenDisconnected
        // Legacy flat keys (≤0.4.x). Read once during migration, never written.
        case networkMode, ssid, modemIP, stats, showBatteryPercent, batteryNotifications
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = AppSettings.defaults
        refreshInterval = try c.decodeIfPresent(TimeInterval.self, forKey: .refreshInterval) ?? d.refreshInterval
        language = try c.decodeIfPresent(AppLanguage.self, forKey: .language) ?? .system
        showWhenDisconnected = try c.decodeIfPresent(Bool.self, forKey: .showWhenDisconnected)
            ?? d.showWhenDisconnected

        if let stored = try c.decodeIfPresent([ModemProfile].self, forKey: .profiles),
           !stored.isEmpty {
            profiles = stored
        } else if c.contains(.profiles) {
            // Stored but empty: repair the never-empty invariant.
            profiles = d.profiles
        } else {
            // Legacy flat payload: fold every device-scoped key into one ZTE
            // profile so nothing the user configured is lost.
            var p = ModemProfile.makeDefault(provider: .zte)
            // The raw values of the retired `NetworkMode` enum.
            if try c.decodeIfPresent(String.self, forKey: .networkMode) == "byIPReachable" {
                p.matchMode = .ipProbe
            }
            p.ssid = try c.decodeIfPresent(String.self, forKey: .ssid) ?? p.ssid
            p.modemIP = try c.decodeIfPresent(String.self, forKey: .modemIP) ?? p.modemIP
            p.stats = try c.decodeIfPresent(StatVisibility.self, forKey: .stats) ?? p.stats
            p.showBatteryPercent = try c.decodeIfPresent(Bool.self, forKey: .showBatteryPercent)
                ?? p.showBatteryPercent
            p.batteryNotifications = try c.decodeIfPresent(BatteryNotificationSettings.self,
                                                           forKey: .batteryNotifications)
                ?? p.batteryNotifications
            profiles = [p]
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(profiles, forKey: .profiles)
        try c.encode(refreshInterval, forKey: .refreshInterval)
        try c.encode(language, forKey: .language)
        try c.encode(showWhenDisconnected, forKey: .showWhenDisconnected)
    }

    init() {}
}

// MARK: - Transitional accessors (DELETED in the "settings UI" task)
// The views and `ModemStore` still bind the old flat names; each forwards to
// the single v1 profile so this schema change ships green on its own.
extension AppSettings {
    var networkMode: NetworkMode {
        get { profiles[0].matchMode == .ssid ? .bySSID : .byIPReachable }
        set { profiles[0].matchMode = (newValue == .bySSID) ? .ssid : .ipProbe }
    }
    var ssid: String {
        get { profiles[0].ssid }
        set { profiles[0].ssid = newValue }
    }
    var modemIP: String {
        get { profiles[0].modemIP }
        set { profiles[0].modemIP = newValue }
    }
    var stats: StatVisibility {
        get { profiles[0].stats }
        set { profiles[0].stats = newValue }
    }
    var showBatteryPercent: Bool {
        get { profiles[0].showBatteryPercent }
        set { profiles[0].showBatteryPercent = newValue }
    }
    var batteryNotifications: BatteryNotificationSettings {
        get { profiles[0].batteryNotifications }
        set { profiles[0].batteryNotifications = newValue }
    }
}
```

- [ ] **Step 4: Extend `SettingsStore`** — in `Sources/ZteMenu/SettingsStore.swift` add the accessor and the save-after-load, keeping `modemBaseURL` as-is (it now reads through the transitional `ssid`/`modemIP` accessors and dies in Task 9):

```swift
    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: key),
           let loaded = try? JSONDecoder().decode(AppSettings.self, from: data) {
            settings = loaded
        } else {
            settings = AppSettings.defaults
        }
        // Persist immediately: a legacy payload migrates on first read, and
        // writing it back pins the migrated profile's UUID across launches.
        save()
    }

    /// v1 manages exactly one device; the settings window edits this profile.
    var profile: ModemProfile {
        get { settings.profiles[0] }
        set { settings.profiles[0] = newValue }
    }
```

- [ ] **Step 5: Run the full suite** (existing `SettingsStoreTests` must pass through the accessors unchanged)

Run: `swift test 2>&1 | tail -3`
Expected: PASS, 0 failures — delta: +6 (the migration tests); every pre-existing `SettingsStoreTests` case passes untouched through the transitional accessors.

- [ ] **Step 6: Commit**

```bash
git add -A && git commit -m "feat(settings): store a list of device profiles and migrate legacy keys"
```

---

### Task 5: `ModemMatcher` — which device am I next to?

Replaces `NetworkDetector`'s job with profile-list semantics, and deletes the dead `WiFiMonitor` (only its own tests use it). `NetworkDetector` itself survives until Task 6 flips `ModemStore` over.

**Files:**
- Create: `Sources/ZteMenu/Modem/ModemMatcher.swift`
- Modify: `Sources/ZteMenu/WiFiMonitor.swift` → deleted (`SSIDReading`/`CoreWLANReader` move to the new file)
- Delete: `Tests/ZteMenuTests/WiFiMonitorTests.swift`
- Test: `Tests/ZteMenuTests/ModemMatcherTests.swift` (new)

**Interfaces:**
- Produces: `enum MatchResult: Equatable { case matched(ModemProfile); case none(ssidSkipped: Bool) }`; `struct ModemMatcher { init(reader: SSIDReading = CoreWLANReader()); @MainActor func match(in: [ModemProfile], locationAuthorized: Bool, probe: (ModemProfile) async -> Bool) async -> MatchResult }`. `SSIDReading` and `CoreWLANReader` keep their exact current declarations, now in `ModemMatcher.swift`.
- Consumes: `ModemProfile`, `MatchMode` (Task 3).

- [ ] **Step 1: Write the failing tests** — `Tests/ZteMenuTests/ModemMatcherTests.swift`:

```swift
import XCTest
@testable import ZteMenu

private struct FixedSSID: SSIDReading {
    let value: String?
    func currentSSID() -> String? { value }
}

@MainActor
final class ModemMatcherTests: XCTestCase {
    private func profile(_ mode: MatchMode, ssid: String = "ZTE_B4B622",
                         ip: String = "192.168.0.1") -> ModemProfile {
        ModemProfile(provider: .zte, matchMode: mode, ssid: ssid, modemIP: ip)
    }

    func testSSIDMatch() async {
        let target = profile(.ssid)
        let m = ModemMatcher(reader: FixedSSID(value: "ZTE_B4B622"))
        let r = await m.match(in: [target], locationAuthorized: true) { _ in false }
        guard case .matched(let p) = r else { return XCTFail("expected a match") }
        XCTAssertEqual(p.id, target.id)
    }

    func testSSIDMismatchAndNoWiFiDoNotMatch() async {
        for current in ["SomeOtherNetwork", nil] {
            let m = ModemMatcher(reader: FixedSSID(value: current))
            let r = await m.match(in: [profile(.ssid)], locationAuthorized: true) { _ in false }
            XCTAssertEqual(r, .none(ssidSkipped: false))
        }
    }

    func testProbeMatchAsksTheProfileDriver() async {
        let m = ModemMatcher(reader: FixedSSID(value: nil))
        var probed: [String] = []
        let r = await m.match(in: [profile(.ipProbe, ip: "10.0.0.1")],
                              locationAuthorized: true) { p in
            probed.append(p.modemIP)
            return true
        }
        XCTAssertEqual(probed, ["10.0.0.1"])
        guard case .matched(let p) = r else { return XCTFail("expected a match") }
        XCTAssertEqual(p.modemIP, "10.0.0.1")
    }

    func testFirstMatchWins() async {
        let first = profile(.ssid, ssid: "Shared")
        let second = profile(.ssid, ssid: "Shared")
        let m = ModemMatcher(reader: FixedSSID(value: "Shared"))
        let r = await m.match(in: [first, second], locationAuthorized: true) { _ in false }
        guard case .matched(let p) = r else { return XCTFail("expected a match") }
        XCTAssertEqual(p.id, first.id)
    }

    func testDeniedLocationSkipsSSIDProfilesAndReportsIt() async {
        let m = ModemMatcher(reader: FixedSSID(value: "ZTE_B4B622"))
        let r = await m.match(in: [profile(.ssid)], locationAuthorized: false) { _ in false }
        XCTAssertEqual(r, .none(ssidSkipped: true))
    }

    func testDeniedLocationStillProbesIPProfiles() async {
        // The refinement over the old behaviour: a denied permission only
        // blocks SSID matching, not the whole app.
        let m = ModemMatcher(reader: FixedSSID(value: nil))
        let r = await m.match(in: [profile(.ssid), profile(.ipProbe)],
                              locationAuthorized: false) { _ in true }
        guard case .matched(let p) = r else { return XCTFail("expected the ip profile") }
        XCTAssertEqual(p.matchMode, .ipProbe)
    }

    func testNothingConfiguredMeansNoMatchNoSkip() async {
        let m = ModemMatcher(reader: FixedSSID(value: "Anything"))
        let r = await m.match(in: [], locationAuthorized: true) { _ in true }
        XCTAssertEqual(r, .none(ssidSkipped: false))
    }
}
```

- [ ] **Step 2: Run to verify failure**

Run: `swift test --filter ModemMatcherTests 2>&1 | tail -5`
Expected: COMPILE ERROR — `cannot find 'ModemMatcher' in scope`.

- [ ] **Step 3: Implement** — `Sources/ZteMenu/Modem/ModemMatcher.swift`:

```swift
import Foundation
import CoreWLAN

public protocol SSIDReading: Sendable {
    func currentSSID() -> String?
}

public struct CoreWLANReader: SSIDReading {
    public init() {}

    public func currentSSID() -> String? {
        CWWiFiClient.shared().interface()?.ssid()
    }
}

/// The outcome of scanning the profile list for a nearby device.
enum MatchResult: Equatable {
    case matched(ModemProfile)
    /// Nothing matched. `ssidSkipped` reports whether any `.ssid` profile
    /// could not be evaluated because location permission is denied — the
    /// difference between "hide the icon" and "explain the permission".
    case none(ssidSkipped: Bool)
}

/// Decides which configured device, if any, we are next to right now.
struct ModemMatcher {
    let reader: SSIDReading

    init(reader: SSIDReading = CoreWLANReader()) {
        self.reader = reader
    }

    /// First match wins, in stored order.
    /// - Parameter probe: asks a profile's driver whether its device answers,
    ///   injected so the matcher stays free of HTTP. `@MainActor` because the
    ///   store's driver factory is main-actor-bound.
    @MainActor
    func match(in profiles: [ModemProfile],
               locationAuthorized: Bool,
               probe: (ModemProfile) async -> Bool) async -> MatchResult {
        var ssidSkipped = false
        // One CoreWLAN read per scan, not per profile.
        let currentSSID = locationAuthorized ? reader.currentSSID() : nil
        for profile in profiles {
            switch profile.matchMode {
            case .ssid:
                guard locationAuthorized else {
                    ssidSkipped = true
                    continue
                }
                if currentSSID == profile.ssid { return .matched(profile) }
            case .ipProbe:
                if await probe(profile) { return .matched(profile) }
            }
        }
        return .none(ssidSkipped: ssidSkipped)
    }
}
```

Then delete the dead monitor and move its protocol home:

```bash
git rm Sources/ZteMenu/WiFiMonitor.swift Tests/ZteMenuTests/WiFiMonitorTests.swift
```

(`SSIDReading`/`CoreWLANReader` used to live in `WiFiMonitor.swift`; they are re-declared verbatim in `ModemMatcher.swift` above, so `NetworkDetector.swift` and `GeneralSettingsTab.swift` keep compiling.)

- [ ] **Step 4: Run the full suite**

Run: `swift test 2>&1 | tail -3`
Expected: PASS, 0 failures — delta: +7 matcher tests, −3 deleted `WiFiMonitorTests`.

- [ ] **Step 5: Commit**

```bash
git add -A && git commit -m "feat(modem): profile-aware network matcher with location-aware skipping"
```

---

### Task 6: Drive `ModemStore` from matched profiles

**Files:**
- Modify: `Sources/ZteMenu/ModemStore.swift`
- Delete: `Sources/ZteMenu/NetworkDetector.swift`, `Tests/ZteMenuTests/NetworkDetectorTests.swift`
- Modify: `Tests/ZteMenuTests/ModemStoreTests.swift`

**Interfaces:**
- Produces: `ModemStore.activeProfile: ModemProfile?` (published, `private(set)`); `ModemStore.init(settings:history:matcher: ModemMatcher = ModemMatcher(), driverFactory: @escaping @MainActor (ModemProfile) -> any ModemDriving = …)` — **internal** init (see Global Constraints); refresh semantics: match → fetch through the profile's driver; `.locationDenied` only when nothing matched AND an `.ssid` profile was skipped.
- Consumes: `ModemMatcher`, `MatchResult` (Task 5), `ProviderCatalog` (Task 2), `ModemProfile.baseURL` (Task 3), `Keychain.password()`, `SessionHTTP` (existing). The notifier call stays `notifier?.handle(data)` — Task 7 re-signs it.

- [ ] **Step 1: Rewrite the store tests** — replace `Tests/ZteMenuTests/ModemStoreTests.swift` with:

```swift
import XCTest
@testable import ZteMenu

@MainActor
final class ModemStoreV2Tests: XCTestCase {
    private static let json = Data(#"{"battery_value":"55","signalbar":"5","network_type":"ENDC","total_rx_bytes":"1000","total_tx_bytes":"500"}"#.utf8)

    private struct FakeDriver: ModemDriving {
        var reachable = false
        var error: Error?
        func fetch() async throws -> ModemData {
            if let error { throw error }
            return ZTEClient.parse(try JSONDecoder()
                .decode([String: String].self, from: ModemStoreV2Tests.json))
        }
        func probe() async -> Bool { reachable }
    }

    private func makeStore(mode: MatchMode,
                           currentSSID: String? = nil,
                           reachable: Bool = false,
                           throwing: Error? = nil,
                           history: HistoryStore) -> ModemStore {
        let defaults = UserDefaults(suiteName: "t-\(UUID().uuidString)")!
        let settings = SettingsStore(defaults: defaults)
        settings.profile.matchMode = mode
        settings.profile.ssid = "ZTE_B4B622"
        let matcher = ModemMatcher(reader: FixedSSID(value: currentSSID))
        return ModemStore(settings: settings, history: history, matcher: matcher,
                          driverFactory: { _ in FakeDriver(reachable: reachable, error: throwing) })
    }

    private func tempHistory() -> HistoryStore {
        HistoryStore(fileURL: FileManager.default.temporaryDirectory
                        .appendingPathComponent("h-\(UUID()).json"),
                     now: { Date(timeIntervalSince1970: 100) })
    }

    func testConnectedPublishesTheMatchedProfileAndAddsHistory() async {
        let hist = tempHistory()
        let store = makeStore(mode: .ipProbe, reachable: true, history: hist)
        await store.refresh()
        if case .connected(let d) = store.state {
            XCTAssertEqual(d.batteryPercent, 55)
        } else { XCTFail("expected connected, got \(store.state)") }
        XCTAssertEqual(store.activeProfile?.matchMode, .ipProbe)
        XCTAssertEqual(hist.samples.count, 1)
        XCTAssertEqual(hist.samples.last?.totalBytes, 1500)
    }

    func testSSIDMatchConnects() async {
        let store = makeStore(mode: .ssid, currentSSID: "ZTE_B4B622",
                              reachable: false, history: tempHistory())
        await store.refresh()
        guard case .connected = store.state else {
            return XCTFail("expected connected, got \(store.state)")
        }
    }

    func testNoMatchHidesAndClearsTheProfile() async {
        let hist = tempHistory()
        let store = makeStore(mode: .ipProbe, reachable: false, history: hist)
        await store.refresh()
        XCTAssertEqual(store.state, .hidden)
        XCTAssertNil(store.activeProfile)
        XCTAssertTrue(hist.samples.isEmpty)
    }

    func testDeniedLocationWithSSIDProfileIsLocationDenied() async {
        let store = makeStore(mode: .ssid, currentSSID: "ZTE_B4B622", history: tempHistory())
        store.setLocationAuth(.denied)
        await store.refresh()
        XCTAssertEqual(store.state, .locationDenied)
        XCTAssertNil(store.activeProfile)
    }

    func testDeniedLocationStillConnectsThroughAnIPProfile() async {
        // The behavioural refinement this refactor buys: location only gates
        // SSID matching, not the whole app.
        let store = makeStore(mode: .ipProbe, reachable: true, history: tempHistory())
        store.setLocationAuth(.denied)
        await store.refresh()
        guard case .connected = store.state else {
            return XCTFail("expected connected, got \(store.state)")
        }
    }

    func testLoginFailureMapsToError() async {
        let store = makeStore(mode: .ipProbe, reachable: true,
                              throwing: ModemError.loginFailed, history: tempHistory())
        await store.refresh()
        XCTAssertEqual(store.state, .error(.loginFailed))
    }

    func testOtherFetchFailureMapsToUnreachable() async {
        struct Boom: Error {}
        let store = makeStore(mode: .ipProbe, reachable: true,
                              throwing: Boom(), history: tempHistory())
        await store.refresh()
        XCTAssertEqual(store.state, .error(.unreachable))
    }
}

private struct FixedSSID: SSIDReading {
    let value: String?
    func currentSSID() -> String? { value }
}
```

- [ ] **Step 2: Run to verify failure**

Run: `swift test --filter ModemStoreV2Tests 2>&1 | tail -5`
Expected: COMPILE ERROR — `ModemStore` has no `matcher`/`driverFactory` init and no `activeProfile`.

- [ ] **Step 3: Rewrite `ModemStore`** — `Sources/ZteMenu/ModemStore.swift` becomes:

```swift
import Foundation
import Observation

@MainActor
@Observable
public final class ModemStore {
    private(set) var state: AppState = .hidden
    /// The device the last refresh matched. The popover header and the menu
    /// bar label read their per-device presentation preferences from it.
    private(set) var activeProfile: ModemProfile?
    private let settings: SettingsStore
    let history: HistoryStore
    private let matcher: ModemMatcher
    private let driverFactory: @MainActor (ModemProfile) -> any ModemDriving
    private var locationAuth: LocationAuth = .authorized
    /// Optional so tests get a store that posts nothing; the app wires one in.
    private var notifier: BatteryNotifier?

    init(settings: SettingsStore,
         history: HistoryStore,
         matcher: ModemMatcher = ModemMatcher(),
         driverFactory: @escaping @MainActor (ModemProfile) -> any ModemDriving = { profile in
             ProviderCatalog.descriptor(for: profile.provider)
                 .makeDriver(profile.baseURL, Keychain.password(), SessionHTTP())
         }) {
        self.settings = settings
        self.history = history
        self.matcher = matcher
        self.driverFactory = driverFactory
    }

    func setBatteryNotifier(_ notifier: BatteryNotifier) {
        self.notifier = notifier
    }

    func setLocationAuth(_ auth: LocationAuth) {
        locationAuth = auth
    }

    func refresh() async {
        let result = await matcher.match(in: settings.settings.profiles,
                                         locationAuthorized: locationAuth != .denied,
                                         probe: { await self.driverFactory($0).probe() })
        switch result {
        case .none(ssidSkipped: true):
            activeProfile = nil
            state = .locationDenied
        case .none(ssidSkipped: false):
            activeProfile = nil
            state = .hidden
        case .matched(let profile):
            activeProfile = profile
            let driver = driverFactory(profile)
            do {
                let data = try await driver.fetch()
                state = .connected(data)
                history.add(battery: data.batteryPercent, totalBytes: data.totalBytesForHistory)
                notifier?.handle(data)
            } catch ModemError.loginFailed {
                state = .error(.loginFailed)
            } catch {
                state = .error(.unreachable)
            }
        }
    }
}
```

Delete the retired detector:

```bash
git rm Sources/ZteMenu/NetworkDetector.swift Tests/ZteMenuTests/NetworkDetectorTests.swift
```

(`ReachabilityChecking`/`URLReachability` lived there; nothing references them anymore — `ZTEClient.probe()` took over in Task 1.)

- [ ] **Step 4: Run the full suite** (`AppDelegate` compiles unchanged — it never passed a detector)

Run: `swift test 2>&1 | tail -3`
Expected: PASS, 0 failures — delta: 7 store tests replace the old 4, −4 deleted `NetworkDetectorTests`.

- [ ] **Step 5: Commit**

```bash
git add -A && git commit -m "refactor(modem): drive the refresh loop from matched profiles"
```

---

### Task 7: Battery alerts scoped to the active profile

**Files:**
- Modify: `Sources/ZteMenu/BatteryNotifier.swift`
- Modify: `Sources/ZteMenu/ModemStore.swift` (the `notifier?.handle` call site)
- Test: `Tests/ZteMenuTests/BatteryNotifierTests.swift` (new)

**Interfaces:**
- Produces: `BatteryNotifier.handle(_ data: ModemData, profile: ModemProfile)` — reads `profile.batteryNotifications`, returns early unless the profile's provider `hasBattery`, and resets its `BatteryAlertDecider` whenever `profile.id` changes; `requestAuthorizationIfNeeded()` scans all profiles of battery-capable providers.
- Consumes: `ProviderCatalog` (Task 2), `ModemProfile` (Task 3), `ModemStore.activeProfile` (Task 6). `BatteryAlertDecider` itself is untouched.

- [ ] **Step 1: Write the failing tests** — `Tests/ZteMenuTests/BatteryNotifierTests.swift`:

```swift
import XCTest
@testable import ZteMenu

@MainActor
private final class SpyPresenter: BatteryAlertPresenting {
    var presented: [BatteryAlert] = []
    var authorizationRequests = 0
    func present(_ alert: BatteryAlert) { presented.append(alert) }
    func requestAuthorization() { authorizationRequests += 1 }
}

@MainActor
final class BatteryNotifierTests: XCTestCase {
    private func makeSettings() -> SettingsStore {
        SettingsStore(defaults: UserDefaults(suiteName: "bn-\(UUID().uuidString)")!)
    }

    private func reading(_ percent: Int) -> ModemData {
        ZTEClient.parse(["battery_value": "\(percent)", "battery_charging": "0",
                         "signalbar": "5", "network_type": "ENDC"])
    }

    func testReadsTheProfilesOwnConfiguration() {
        let settings = makeSettings()
        var profile = ModemProfile.makeDefault(provider: .zte)
        // Only one threshold, at 50 — NOT the defaults (20/10) — so an alert
        // at 45 proves the notifier read the profile, not a global.
        for t in profile.batteryNotifications.thresholds {
            profile.batteryNotifications.removeThreshold(id: t.id)
        }
        profile.batteryNotifications.addThreshold(percent: 50)
        let spy = SpyPresenter()
        let notifier = BatteryNotifier(settings: settings, presenter: spy)

        notifier.handle(reading(60), profile: profile)   // baseline
        notifier.handle(reading(45), profile: profile)   // crossing

        XCTAssertEqual(spy.presented, [.threshold(percent: 45, isUrgent: false)])
    }

    func testSwitchingProfilesResetsTheDecider() {
        // A new device's first reading is a baseline, not a crossing: profile
        // B sitting at 15% must stay quiet even though profile A armed
        // nothing at that level.
        let settings = makeSettings()
        let a = ModemProfile.makeDefault(provider: .zte)
        let b = ModemProfile.makeDefault(provider: .zte)
        let spy = SpyPresenter()
        let notifier = BatteryNotifier(settings: settings, presenter: spy)

        notifier.handle(reading(100), profile: a)  // A's baseline, high
        notifier.handle(reading(15), profile: b)   // B appears already low

        XCTAssertTrue(spy.presented.isEmpty,
                      "a level the new device was already at is not a crossing")
    }

    func testSameProfileKeepsItsDeciderMemory() {
        let settings = makeSettings()
        let profile = ModemProfile.makeDefault(provider: .zte)  // thresholds 20/10
        let spy = SpyPresenter()
        let notifier = BatteryNotifier(settings: settings, presenter: spy)

        notifier.handle(reading(60), profile: profile)
        notifier.handle(reading(15), profile: profile)  // crosses 20 → fires
        notifier.handle(reading(14), profile: profile)  // still below → quiet

        XCTAssertEqual(spy.presented.count, 1)
    }

    func testAuthorizationPromptScansTheProfiles() {
        let settings = makeSettings()  // default ZTE profile, thresholds armed
        let spy = SpyPresenter()
        BatteryNotifier(settings: settings, presenter: spy).requestAuthorizationIfNeeded()
        XCTAssertEqual(spy.authorizationRequests, 1)
    }

    func testNoArmedAlertMeansNoPrompt() {
        let settings = makeSettings()
        for t in settings.profile.batteryNotifications.thresholds {
            settings.profile.batteryNotifications.updateThreshold(id: t.id, isEnabled: false)
        }
        settings.profile.batteryNotifications.fullEnabled = false
        let spy = SpyPresenter()
        BatteryNotifier(settings: settings, presenter: spy).requestAuthorizationIfNeeded()
        XCTAssertEqual(spy.authorizationRequests, 0)
    }
}
```

- [ ] **Step 2: Run to verify failure**

Run: `swift test --filter BatteryNotifierTests 2>&1 | tail -5`
Expected: COMPILE ERROR — `handle` takes no `profile:` argument.

- [ ] **Step 3: Implement** — in `Sources/ZteMenu/BatteryNotifier.swift`, replace the `BatteryNotifier` class body's state and two methods (decider, `handle`, `requestAuthorizationIfNeeded`; inits and everything else stay):

```swift
    private var decider = BatteryAlertDecider()
    /// Which device the decider's memory belongs to. The hysteresis state is
    /// per-device: one modem's charge level must not arm or silence another's.
    private var deciderProfileID: UUID?

    func handle(_ data: ModemData, profile: ModemProfile) {
        // Defence in depth next to the nil-percent guard: a provider without
        // a battery has no alerts, whatever the profile's stored config says.
        guard ProviderCatalog.descriptor(for: profile.provider).capabilities.hasBattery else { return }
        if deciderProfileID != profile.id {
            decider = BatteryAlertDecider()
            deciderProfileID = profile.id
        }
        guard let percent = data.batteryPercent else { return }
        guard let alert = decider.decide(percent: percent,
                                         isCharging: data.isCharging,
                                         settings: profile.batteryNotifications) else { return }
        presenter.present(alert)
    }

    /// Called when the user turns an alert on in settings, and at launch.
    func requestAuthorizationIfNeeded() {
        let armed = settings.settings.profiles.contains { profile in
            ProviderCatalog.descriptor(for: profile.provider).capabilities.hasBattery
                && profile.batteryNotifications.isAnyEnabled
        }
        guard armed else { return }
        presenter.requestAuthorization()
    }
```

In `Sources/ZteMenu/ModemStore.swift`, the connected branch's call becomes:

```swift
                notifier?.handle(data, profile: profile)
```

- [ ] **Step 4: Run the full suite**

Run: `swift test 2>&1 | tail -3`
Expected: PASS, 0 failures — delta: +5 (the notifier tests).

- [ ] **Step 5: Commit**

```bash
git add -A && git commit -m "feat(battery): scope battery alerts and state to the active profile"
```

---

### Task 8: Present the active profile — menu bar label and popover header

**Files:**
- Modify: `Sources/ZteMenu/ZteMenuApp.swift`
- Modify: `Sources/ZteMenu/PopoverView.swift`
- Modify: `Tests/ZteMenuTests/PopoverViewKeyTests.swift` (add header tests)

**Interfaces:**
- Produces: `PopoverView.headerText(for profile: ModemProfile) -> String` (static, pure); the menu bar percentage reads `store.activeProfile?.showBatteryPercent ?? false`; popover stat sections read the active profile's `stats`.
- Consumes: `ModemStore.activeProfile` (Task 6), `ProviderCatalog` (Task 2), `SettingsStore.profile` (Task 4). `MenuBarPresentation` is untouched.

- [ ] **Step 1: Write the failing tests** — append to `Tests/ZteMenuTests/PopoverViewKeyTests.swift`:

```swift
    func testHeaderShowsBrandAndSSIDWhenMatchedBySSID() {
        var p = ModemProfile.makeDefault(provider: .zte)
        p.matchMode = .ssid
        p.ssid = "ZTE_B4B622"
        XCTAssertEqual(PopoverView.headerText(for: p), "ZTE · ZTE_B4B622")
    }

    func testHeaderShowsBrandAndIPWhenMatchedByProbe() {
        var p = ModemProfile.makeDefault(provider: .zte)
        p.matchMode = .ipProbe
        p.modemIP = "10.0.0.1"
        XCTAssertEqual(PopoverView.headerText(for: p), "ZTE · 10.0.0.1")
    }
```

- [ ] **Step 2: Run to verify failure**

Run: `swift test --filter PopoverViewKeyTests 2>&1 | tail -5`
Expected: COMPILE ERROR — `type 'PopoverView' has no member 'headerText'`.

- [ ] **Step 3: Implement the popover changes** — in `Sources/ZteMenu/PopoverView.swift`:

Add the pure helper next to the existing `static func key` helpers:

```swift
    /// "ZTE · ZTE_B4B622" — the provider's brand plus whichever identifier
    /// the profile matches by. Pure so the header is unit-testable.
    static func headerText(for profile: ModemProfile) -> String {
        let name = ProviderCatalog.descriptor(for: profile.provider).displayName
        let identifier = profile.matchMode == .ssid ? profile.ssid : profile.modemIP
        return "\(name) · \(identifier)"
    }
```

In `content`, hand the profile to the connected builder (the store publishes it in every `.connected` refresh; the settings profile is a formal fallback):

```swift
        case .connected(let d):
            connected(d, profile: store.activeProfile ?? settings.profile)
```

Re-sign the builder and swap the header line and the stat gates from global settings to the profile:

```swift
    @ViewBuilder
    private func connected(_ d: ModemData, profile: ModemProfile) -> some View {
        Text(Self.headerText(for: profile))
            .font(.headline)
        if let p = d.provider {
            Text("\(p) · \(d.networkLabel)").foregroundStyle(.secondary)
        }
        if profile.stats.basic {
            statSection(d)
        }
        if profile.stats.radio {
            radioSection(d)
        }
        if profile.stats.transfer {
            transferSection(d)
        }
        if profile.stats.uptime, let up = d.sessionUptime {
            row("timer", l10n(.popoverSession), ByteFormat.uptime(up))
        }
        if !store.history.batterySeries().isEmpty {
            BatteryChartView(samples: store.history.batterySeries())
                .frame(height: 60)
        }
    }
```

- [ ] **Step 4: Point the menu bar label at the profile** — in `Sources/ZteMenu/ZteMenuApp.swift`:

```swift
        let p = MenuBarPresentation.make(for: store.state,
                                         showBatteryPercent: store.activeProfile?.showBatteryPercent ?? false,
                                         showWhenDisconnected: settings.settings.showWhenDisconnected)
```

- [ ] **Step 5: Run the full suite**

Run: `swift test 2>&1 | tail -3`
Expected: PASS, 0 failures — delta: +2 (the header tests).

- [ ] **Step 6: Commit**

```bash
git add -A && git commit -m "feat(menubar): present the active profile in the header and battery label"
```

---

### Task 9: Settings UI on the profile — provider picker, capability gating, shim removal

The UI stops using the transitional accessors; they and `NetworkMode` are deleted. This is the only task that touches files the parallel session has been polishing (`BatterySettingsTab`) — change ONLY the binding paths there; keep the row layout exactly as found.

**Files:**
- Modify: `Sources/ZteMenu/Modem/ModemProfile.swift` (add `adopting(provider:)`)
- Modify: `Sources/ZteMenu/Settings/SettingsTab.swift` (add `visible(for:)`)
- Modify: `Sources/ZteMenu/Settings/GeneralSettingsTab.swift`
- Modify: `Sources/ZteMenu/Settings/PanelSettingsTab.swift`
- Modify: `Sources/ZteMenu/Settings/BatterySettingsTab.swift`
- Modify: `Sources/ZteMenu/SettingsView.swift`
- Modify: `Sources/ZteMenu/AppSettings.swift` (delete the transitional extension and `NetworkMode`)
- Modify: `Sources/ZteMenu/SettingsStore.swift` (delete `modemBaseURL`)
- Modify: `Sources/ZteMenu/Localization/LocKey.swift`, `Resources/en.lproj/Localizable.strings`, `Resources/pl.lproj/Localizable.strings`
- Modify: `Tests/ZteMenuTests/ModemProfileTests.swift`, `Tests/ZteMenuTests/SettingsTabTests.swift`, `Tests/ZteMenuTests/SettingsStoreTests.swift`

**Interfaces:**
- Produces: `ModemProfile.adopting(provider:) -> ModemProfile`; `SettingsTab.visible(for provider: ProviderKind) -> [SettingsTab]`; `LocKey.settingsDeviceType = "settings.network.device_type"`. After this task the flat accessor names (`settings.settings.ssid` etc.) and `NetworkMode` no longer exist.
- Consumes: `SettingsStore.profile` (Task 4), `ProviderCatalog`/`ModemCapabilities` (Task 2).

- [ ] **Step 1: Write the failing tests.** Append to `Tests/ZteMenuTests/ModemProfileTests.swift`:

```swift
    func testAdoptingAProviderKeepsTypedValues() {
        var p = ModemProfile.makeDefault(provider: .zte)
        p.ssid = "MyNetwork"
        p.modemIP = "10.0.0.7"
        p.matchMode = .ipProbe
        let adopted = p.adopting(provider: .zte)
        XCTAssertEqual(adopted.ssid, "MyNetwork")
        XCTAssertEqual(adopted.modemIP, "10.0.0.7")
        XCTAssertEqual(adopted.matchMode, .ipProbe,
                       "a supported mode survives the switch")
        XCTAssertEqual(adopted.id, p.id, "adopting a provider is not a new device")
    }

    func testAdoptingAProviderPrefillsEmptyFields() {
        var p = ModemProfile.makeDefault(provider: .zte)
        p.ssid = ""
        p.modemIP = ""
        let adopted = p.adopting(provider: .zte)
        XCTAssertEqual(adopted.ssid, "ZTE_B4B622")
        XCTAssertEqual(adopted.modemIP, "192.168.0.1")
    }
```

(The match-mode *clamp* branch — a mode the new provider does not support — is unreachable while ZTE supports every mode; it gets its test the day a second provider lands.)

Append to `Tests/ZteMenuTests/SettingsTabTests.swift`:

```swift
    func testEveryTabIsVisibleForABatteryCapableProvider() {
        // ZTE has a battery, so today every tab is visible; the filter itself
        // is the seam a battery-less provider will flow through.
        XCTAssertEqual(SettingsTab.visible(for: .zte), SettingsTab.allCases)
    }
```

- [ ] **Step 2: Run to verify failure**

Run: `swift test --filter "ModemProfileTests|SettingsTabTests" 2>&1 | tail -5`
Expected: COMPILE ERROR — no `adopting(provider:)`, no `visible(for:)`.

- [ ] **Step 3: Implement the pure helpers.** In `Sources/ZteMenu/Modem/ModemProfile.swift`, inside the struct:

```swift
    /// The profile after the user switches its provider in settings: the
    /// match mode is clamped to what the new provider supports, and only
    /// EMPTY address fields adopt the new defaults — typed values survive.
    func adopting(provider newProvider: ProviderKind) -> ModemProfile {
        var p = self
        p.provider = newProvider
        let d = ProviderCatalog.descriptor(for: newProvider)
        if !d.supportedMatchModes.contains(p.matchMode) {
            p.matchMode = d.defaultMatchMode
        }
        if p.ssid.isEmpty { p.ssid = d.defaultSSID }
        if p.modemIP.isEmpty { p.modemIP = d.defaultBaseURL.host ?? p.modemIP }
        return p
    }
```

In `Sources/ZteMenu/Settings/SettingsTab.swift`:

```swift
    /// The tabs that make sense for the edited profile's provider — a device
    /// without a battery simply has no battery tab.
    static func visible(for provider: ProviderKind) -> [SettingsTab] {
        let capabilities = ProviderCatalog.descriptor(for: provider).capabilities
        return allCases.filter { $0 != .battery || capabilities.hasBattery }
    }
```

- [ ] **Step 4: Localize the picker.** In `Sources/ZteMenu/Localization/LocKey.swift`, after `case settingsNetworkSection…` line, add:

```swift
    case settingsDeviceType = "settings.network.device_type"
```

`Resources/en.lproj/Localizable.strings`, in the `/* Settings — network */` block after the `"settings.network.section"` line, add; and change the SSID field's brand-specific label:

```
"settings.network.device_type" = "Device type";
```

```
"settings.network.ssid_field" = "Modem Wi-Fi name";
```

`Resources/pl.lproj/Localizable.strings`, same block:

```
"settings.network.device_type" = "Typ urządzenia";
```

```
"settings.network.ssid_field" = "Nazwa sieci Wi-Fi modemu";
```

- [ ] **Step 5: Rebind the tabs.** `Sources/ZteMenu/Settings/GeneralSettingsTab.swift` — the network `Section` becomes (login-item section and appearance section unchanged):

```swift
            Section {
                Picker(l10n(.settingsDeviceType), selection: Binding(
                    get: { settings.profile.provider },
                    set: { settings.profile = settings.profile.adopting(provider: $0) }
                )) {
                    ForEach(ProviderKind.allCases, id: \.self) { kind in
                        Text(ProviderCatalog.descriptor(for: kind).displayName).tag(kind)
                    }
                }
                Picker(l10n(.settingsDetectionMode), selection: $settings.profile.matchMode) {
                    ForEach(ProviderCatalog.descriptor(for: settings.profile.provider)
                                .supportedMatchModes, id: \.self) { mode in
                        Text(l10n(mode == .ssid ? .settingsDetectionBySSID
                                                : .settingsDetectionByIP)).tag(mode)
                    }
                }
                LabeledContent(l10n(.settingsCurrentNetwork),
                               value: currentSSID ?? l10n(.placeholderDash))

                if settings.profile.matchMode == .ssid {
                    TextField(l10n(.settingsSSIDField), text: $settings.profile.ssid)
                        .help(l10n(.settingsSSIDHelp))
                } else {
                    TextField(l10n(.settingsModemIPField), text: $settings.profile.modemIP)
                        .help(l10n(.settingsModemIPHelp))
                }
            }
```

`Sources/ZteMenu/Settings/PanelSettingsTab.swift` — the stats section binds to the profile (`showWhenDisconnected` stays app-scoped):

```swift
            Section {
                Toggle(l10n(.settingsStatsBasic), isOn: $settings.profile.stats.basic)
                Toggle(l10n(.settingsStatsRadio), isOn: $settings.profile.stats.radio)
                Toggle(l10n(.settingsStatsTransfer), isOn: $settings.profile.stats.transfer)
                Toggle(l10n(.settingsStatsUptime), isOn: $settings.profile.stats.uptime)
            }
```

`Sources/ZteMenu/Settings/BatterySettingsTab.swift` — binding paths ONLY (layout as found): `settings.settings.batteryNotifications` → `settings.profile.batteryNotifications` (the `alerts` computed property and every `updateThreshold`/`addThreshold`/`removeThreshold`/`fullEnabled` write), and `$settings.settings.showBatteryPercent` → `$settings.profile.showBatteryPercent`.

`Sources/ZteMenu/SettingsView.swift` — gate the tab list:

```swift
        TabView {
            ForEach(SettingsTab.visible(for: settings.profile.provider)) { tab in
                content(for: tab)
                    .tabItem { Label(l10n(tab.titleKey), systemImage: tab.symbolName) }
                    .tag(tab)
            }
        }
```

- [ ] **Step 6: Delete the transitional layer.** Remove from `Sources/ZteMenu/AppSettings.swift`: the whole `// MARK: - Transitional accessors` extension and the `NetworkMode` enum. Remove `modemBaseURL` from `Sources/ZteMenu/SettingsStore.swift`. In `Tests/ZteMenuTests/SettingsStoreTests.swift`, retarget the flat-path assertions:

```swift
    func testDefaults() {
        let store = SettingsStore(defaults: freshDefaults())
        XCTAssertEqual(store.profile.ssid, "ZTE_B4B622")
        XCTAssertEqual(store.profile.modemIP, "192.168.0.1")
        XCTAssertEqual(store.profile.matchMode, .ssid)
        XCTAssertEqual(store.settings.refreshInterval, 60)
        XCTAssertTrue(store.profile.stats.basic)
        XCTAssertTrue(store.profile.stats.transfer)
        XCTAssertFalse(store.settings.showWhenDisconnected, "the icon hides by default")
    }

    func testPersistsAcrossInstances() {
        let d = freshDefaults()
        let a = SettingsStore(defaults: d)
        a.profile.ssid = "MyZTE"
        a.profile.matchMode = .ipProbe
        a.save()

        let b = SettingsStore(defaults: d)
        XCTAssertEqual(b.profile.ssid, "MyZTE")
        XCTAssertEqual(b.profile.matchMode, .ipProbe)
    }

    func testBatteryDefaults() {
        let store = SettingsStore(defaults: freshDefaults())
        XCTAssertFalse(store.profile.showBatteryPercent, "the percentage is opt-in")
        let alerts = store.profile.batteryNotifications
        XCTAssertEqual(alerts.thresholds.map(\.percent), [20, 10])
        XCTAssertTrue(alerts.thresholds.allSatisfy(\.isEnabled))
        XCTAssertFalse(alerts.fullEnabled)
    }

    func testPayloadWithoutBatteryKeysStillLoads() throws {
        let d = freshDefaults()
        let legacy = Data(#"{"networkMode":"byIPReachable","ssid":"MyZTE","modemIP":"10.0.0.1","refreshInterval":30,"stats":{"basic":false,"radio":true,"transfer":true,"uptime":true},"language":"pl"}"#.utf8)
        d.set(legacy, forKey: "zte.settings")

        let store = SettingsStore(defaults: d)
        XCTAssertEqual(store.profile.ssid, "MyZTE")
        XCTAssertEqual(store.settings.language, .pl)
        XCTAssertFalse(store.profile.stats.basic)
        XCTAssertFalse(store.profile.showBatteryPercent)
        XCTAssertFalse(store.settings.showWhenDisconnected)
        XCTAssertEqual(store.profile.batteryNotifications, BatteryNotificationSettings())
    }

    func testBatterySettingsPersist() {
        let d = freshDefaults()
        let a = SettingsStore(defaults: d)
        a.profile.showBatteryPercent = true
        a.profile.batteryNotifications.addThreshold(percent: 35, isUrgent: true)
        a.profile.batteryNotifications.fullEnabled = true
        a.save()

        let b = SettingsStore(defaults: d)
        XCTAssertTrue(b.profile.showBatteryPercent)
        XCTAssertEqual(b.profile.batteryNotifications.thresholds.map(\.percent), [35, 20, 10])
        XCTAssertTrue(b.profile.batteryNotifications.fullEnabled)
    }

    func testProfileBaseURL() {
        let store = SettingsStore(defaults: freshDefaults())
        store.profile.modemIP = "192.168.1.1"
        XCTAssertEqual(store.profile.baseURL.absoluteString, "http://192.168.1.1")
    }
```

(`testModemBaseURL` is replaced by `testProfileBaseURL`.)

- [ ] **Step 7: Run the full suite** (the L10n completeness tests pick the new key up automatically)

Run: `swift test 2>&1 | tail -3`
Expected: PASS, 0 failures — delta: +3 (adopting ×2, tab visibility ×1); the retargeted `SettingsStoreTests` all pass.

- [ ] **Step 8: Commit**

```bash
git add -A && git commit -m "feat(settings): provider picker and per-device settings bindings"
```

---

### Task 10: Retire the legacy remnants and verify end to end

**Files:**
- Modify: `Sources/ZteMenu/Config.swift`
- Modify: `Sources/ZteMenu/Providers/ZTE/ZTEClient.swift` (drop the `Config.modemBaseURL` default argument)
- Modify: `Tests/ZteMenuTests/ConfigTests.swift`, `Tests/ZteMenuTests/ZTEClientTests.swift`

**Interfaces:**
- Produces: `Config` holds only `refreshInterval`; the modem address and SSID defaults live solely in `ZTEProvider.descriptor`.
- Consumes: everything above.

- [ ] **Step 1: Update the tests first.** `Tests/ZteMenuTests/ConfigTests.swift` becomes:

```swift
import XCTest
@testable import ZteMenu

final class ConfigTests: XCTestCase {
    func testRefreshInterval() {
        XCTAssertEqual(Config.refreshInterval, 60)
    }
}
```

In `Tests/ZteMenuTests/ZTEClientTests.swift` (all three classes), replace every `Config.modemBaseURL` with a local constant at the top of the file:

```swift
private let zteURL = URL(string: "http://192.168.0.1")!
```

- [ ] **Step 2: Run to verify failure**

Run: `swift test --filter ConfigTests 2>&1 | tail -5`
Expected: still PASS (the constants exist) — this task's "red" is the next step's compile break; proceed.

- [ ] **Step 3: Shrink `Config`** — `Sources/ZteMenu/Config.swift` becomes:

```swift
import Foundation

enum Config {
    static let refreshInterval: TimeInterval = 60
}
```

In `Sources/ZteMenu/Providers/ZTE/ZTEClient.swift`, the init loses its address default (callers always pass one — the descriptor factory, the store default, and tests):

```swift
    public init(baseURL: URL,
                http: HTTPFetching = URLSession.shared,
                password: String? = nil) {
```

Also check `AppDelegate.swift` still compiles — it references only `Config.refreshInterval`.

- [ ] **Step 4: Guard against resurrection**

Run: `grep -rn "NetworkMode\|WiFiMonitor\|NetworkDetector\|ZTE U50\|targetSSID\|modemBaseURL" Sources Tests --include="*.swift"`
Expected: **no output**. Any hit is an unfinished migration — fix it before continuing.

- [ ] **Step 5: Run the full suite and the app build**

Run: `swift test 2>&1 | tail -3`
Expected: PASS, 0 failures — delta: ±0 (`ConfigTests` shrank by the two removed constants' assertions inside one test method).

Run: `./scripts/build-app.sh 2>&1 | tail -5`
Expected: the `.app` bundle assembles without errors.

- [ ] **Step 6: Manual smoke test** (needs the real modem nearby) — launch the built app and check: the icon appears on the ZTE network; the popover header reads "ZTE · <your SSID>"; General shows the Device type picker with "ZTE"; switching detection mode to "By IP reachability" keeps the icon alive; the Battery tab still edits thresholds; toggling "Show battery percentage" updates the menu bar. Then delete and re-install over a 0.4.x settings payload is already covered by the migration tests — no manual step.

- [ ] **Step 7: Commit**

```bash
git add -A && git commit -m "chore(modem): retire legacy detection code and shrink Config"
```

---

## Post-Plan Notes

- **Release notes:** the popover header changes from "ZTE U50 · <ssid>" to "ZTE · <ssid>", and the SSID field label from "ZTE network name" to "Modem Wi-Fi name". Mention both.
- **Adding a provider later (the acceptance criterion):** create `Sources/ZteMenu/Providers/<Brand>/` with a `ModemDriving` driver + descriptor, add one `ProviderKind` case, wire it in `ProviderCatalog.descriptor(for:)` (the exhaustive switch forces this), add the brand's `defaultSSID`/URL. Nothing else moves.
- **Deliberately deferred:** per-profile Keychain slots (needs multi-profile UI first; path: account = profile UUID + one-time copy from `"modem"`), fingerprint probes (strengthen `ZTEClient.probe()` to parse a goform response), multi-profile management UI.
