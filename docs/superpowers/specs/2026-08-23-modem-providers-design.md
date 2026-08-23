# Design: Provider-based modem architecture

Date: 2026-08-23
Status: approved

## Goal

Decouple the app from the ZTE U50 so that support for other modems and routers
(e.g. an Asus router) can be added by writing a new provider, not by rewriting
the app. Three concepts, today fused together, become separate:

- **Provider** — a device family and its protocol driver (ZTE today, Asus
  later). Declares what the device can do and how to talk to it.
- **Profile** — the user's configured instance: which provider, how to
  recognise its network (SSID or IP probe), its address, and the
  device-scoped preferences (battery alerts, menu bar %, popover sections).
- **Matcher** — the engine that answers "which configured device, if any, am I
  next to right now".

The ZTE provider matches by SSID by default; a future Asus provider would
default to IP probing. Both axes are data on the profile, not logic.

## Scope

In scope:

- A provider abstraction: identity enum, descriptor (metadata + capabilities),
  driver protocol, and a catalog mapping one to the other.
- A `ModemProfile` model and an `AppSettings` schema built around a list of
  profiles, with a lossless migration from the current flat keys.
- Device-scoped ("contextual") settings: battery notifications, menu bar
  battery %, and popover stat visibility move from global settings into the
  profile. Battery UI is gated on the provider's `hasBattery` capability.
- A `ModemMatcher` replacing `NetworkDetector` and the vestigial `WiFiMonitor`.
- The ZTE driver extracted from `ModemClient`/`ModemData.parse` with behaviour
  preserved (same requests, same fields, same login flow).
- Settings and popover UI updated: provider picker, match-mode picker driven by
  the descriptor, popover header no longer hardcoding "ZTE U50".

Out of scope:

- Renaming the app, bundle id, brew cask, or Sparkle feed. The architecture
  becomes brand-neutral internally; rebranding is a separate product decision.
- Multi-profile UI. The schema is a list from day one, but v1 UI manages
  exactly one profile.
- An actual Asus driver (no hardware/API to verify against). The contract that
  will receive it is the deliverable.
- Fingerprint probing (verifying the probed device's identity). The `probe()`
  hook is designed for it; v1 keeps today's HEAD reachability.
- Per-profile Keychain slots. The single `"modem"` account stays until
  multi-profile UI exists; the future path is documented below.

## Architecture

### Core types — `Sources/ZteMenu/Modem/`

```swift
enum ProviderKind: String, Codable, CaseIterable, Sendable {
    case zte
}

enum PasswordRole: Sendable, Equatable {
    case none            // device needs no credentials
    case unlocksTraffic  // status is public; traffic counters need login (ZTE)
    case requiredForAll  // nothing readable without login
}

struct ModemCapabilities: Sendable, Equatable {
    let hasBattery: Bool
    let passwordRole: PasswordRole
}

struct ProviderDescriptor: Sendable {
    let displayName: String                 // "ZTE" — brand names are not localized
    let defaultBaseURL: URL
    let defaultSSID: String                 // prefill for a fresh profile's SSID field
    let supportedMatchModes: [MatchMode]
    let defaultMatchMode: MatchMode
    let capabilities: ModemCapabilities
    let makeDriver: @Sendable (URL, String?, any HTTPFetching) -> any ModemDriving
}

enum ProviderCatalog {
    static func descriptor(for kind: ProviderKind) -> ProviderDescriptor
    // switch over ProviderKind — exhaustive, so a new case without a
    // descriptor is a compile error, not a runtime lookup miss.
}
```

```swift
protocol ModemDriving: Sendable {
    /// Read the device's current state.
    func fetch() async throws -> ModemData
    /// "Is MY device answering at the configured address?" Used by `.ipProbe`
    /// matching. v1 implementations may use plain reachability; a provider can
    /// later strengthen this to a protocol-level fingerprint.
    func probe() async -> Bool
}
```

`ModemData` keeps its name, its all-optional field set, and its derived
properties (`networkLabel`, `signalQuality`, `totalBytesForHistory`).
`ModemData.parse(_:)` — a ZTE-keyed dictionary parser — moves into the ZTE
driver; the struct itself becomes provider-neutral with a memberwise init.
`ModemErrorKind` (`loginFailed`, `unreachable`) and `AppState` are already
provider-neutral and keep their shapes.

### Matching

```swift
enum MatchMode: String, Codable, CaseIterable, Sendable {
    case ssid     // compare the current WiFi SSID (legacy "bySSID")
    case ipProbe  // ask the driver whether the device answers (legacy "byIPReachable")
}

struct ModemProfile: Codable, Equatable, Identifiable, Sendable {
    var id: UUID
    var provider: ProviderKind
    var matchMode: MatchMode
    var ssid: String       // used by .ssid matching
    var modemIP: String    // the driver's address, and the .ipProbe target
    // Device-scoped preferences ("contextual" settings):
    var showBatteryPercent: Bool
    var batteryNotifications: BatteryNotificationSettings
    var stats: StatVisibility
}
```

`matchMode` plus separate `ssid`/`modemIP` fields (rather than an enum with
associated values) is deliberate: toggling the mode picker in Settings must not
erase the other field's text, and it mirrors the tolerant per-field decoding
style the settings already use.

`ModemMatcher` absorbs `NetworkDetector` (and the dead `WiFiMonitor`):

```swift
enum MatchResult: Equatable {
    case matched(ModemProfile)
    /// No profile matched. `ssidSkipped` reports whether any `.ssid` profile
    /// was not evaluated because location permission is denied.
    case none(ssidSkipped: Bool)
}

struct ModemMatcher {
    let reader: SSIDReading   // CoreWLANReader in the app, stub in tests

    func match(in profiles: [ModemProfile],
               locationAuthorized: Bool,
               probe: (ModemProfile) async -> Bool) async -> MatchResult
}
```

Semantics: profiles are evaluated in order; the first match wins. `.ssid`
profiles compare `reader.currentSSID()` against `profile.ssid` and are skipped
(not failed) when location permission is denied. `.ipProbe` profiles await
`probe(profile)`, which the store wires to the profile's driver. This refines
today's location rule: a denied permission only blocks SSID-matched profiles
instead of the whole app, and `.locationDenied` is shown only when nothing
matched *and* an SSID profile had to be skipped. With a single SSID-matched
profile — today's setup — behaviour is identical to current.

`SSIDReading` and `CoreWLANReader` move into the `Modem/` folder unchanged.
`URLReachability` retires: probing goes through each driver's own HTTP stack
(see the ZTE provider below), which keeps it stubbed by the same test seam as
`fetch()`.

### ZTE provider — `Sources/ZteMenu/Providers/ZTE/`

- `ZTEClient` is today's `ModemClient` renamed and conforming to
  `ModemDriving`. Same goform endpoints, field lists, Referer header, LD/SHA256
  login (`ZTEAuth`), and cookie-session requirement (`SessionHTTP`). The ZTE
  key mapping (`ModemData.parse`) lives here.
- `probe()` in v1 issues a HEAD against the base URL through the client's
  injected `HTTPFetching`, with the same 3-second budget the old
  `URLReachability` used — today's `byIPReachable` behaviour, now testable
  through the driver's own seam.
- Descriptor values: displayName `"ZTE"`, defaultBaseURL `http://192.168.0.1`,
  defaultSSID `"ZTE_B4B622"` (today's shipped default), modes
  `[.ssid, .ipProbe]` with `.ssid` default, capabilities
  `hasBattery: true, passwordRole: .unlocksTraffic`.

`HTTPFetching` and `SessionHTTP` remain shared infrastructure — any HTTP-based
provider reuses them.

### Settings scoping

| Scope | Settings | Rationale |
| --- | --- | --- |
| App | `language`, launch at login, `showWhenDisconnected`, `refreshInterval`, updates | Describe the app. `showWhenDisconnected` concerns the "no device matched" state, which has no device context by definition. |
| Profile | match mode, SSID, IP, password, `showBatteryPercent`, `batteryNotifications`, `stats` | Describe one device and how to present it. |

`AppSettings` v2:

```swift
struct AppSettings: Codable, Equatable {
    var profiles: [ModemProfile]          // never empty; default: one ZTE profile
    var refreshInterval: TimeInterval
    var language: AppLanguage
    var showWhenDisconnected: Bool
    // removed: networkMode, ssid, modemIP, stats, showBatteryPercent,
    //          batteryNotifications
}
```

Migration, in the same tolerant custom-decoder style the struct already uses:

- If the `profiles` key is present, decode it; if the decoded array is empty,
  repair to the default ZTE profile (invariant: `profiles` is never empty).
- If `profiles` is absent (legacy payload), build one ZTE profile from the
  legacy keys: `networkMode` (raw `"bySSID"` → `.ssid`, `"byIPReachable"` →
  `.ipProbe`, decoded via a private legacy enum), `ssid`, `modemIP`,
  `showBatteryPercent`, `batteryNotifications`, `stats` — each falling back to
  its default when missing. A fresh `UUID` is generated for the migrated
  profile. Nothing the user configured is lost.
- Encoding writes only the new keys; the legacy keys disappear on first save.

`SettingsStore` gains a `profile` accessor (get/set on `profiles[0]`) so v1 UI
binds `$settings.profile.ssid` etc. without indexing in views. The store keeps
its `modemBaseURL`-style URL derivation, now per profile.

Keychain: unchanged single `"modem"` slot, read at fetch time as today. Future
multi-profile path (documented, not built): account = profile UUID, one-time
migration copying the legacy item to the first profile's slot.

### Runtime flow — `ModemStore`

```
refresh():
  profiles = settings.settings.profiles
  result = await matcher.match(in: profiles,
                               locationAuthorized: locationAuth != .denied,
                               probe: { driverFactory($0).probe() })
  switch result:
    .none(ssidSkipped: true)  → state = .locationDenied ; activeProfile = nil
    .none(ssidSkipped: false) → state = .hidden         ; activeProfile = nil
    .matched(profile):
      activeProfile = profile
      driver = ProviderCatalog.descriptor(for: profile.provider)
                 .makeDriver(baseURL(profile), Keychain.password(), SessionHTTP())
      do: data = try await driver.fetch()
          state = .connected(data); history.add(...); notifier.handle(data, profile)
      catch loginFailed → .error(.loginFailed); catch → .error(.unreachable)
```

`ModemStore` publishes `activeProfile: ModemProfile?` alongside `state`. The
injected `clientFactory` becomes a `driverFactory: (ModemProfile) ->
any ModemDriving` so tests keep stubbing at the same seam.

### Battery contextualization

- `BatteryNotifier.handle(_:profile:)` reads `profile.batteryNotifications`
  and returns early when the profile's provider has `hasBattery == false`
  (defence in depth next to the existing nil-percent guard).
- The `BatteryAlertDecider` is a hysteresis state machine, so its state is
  per-device: the notifier tracks the profile id it last handled and resets
  the decider when the active profile changes. One device's charge level must
  not arm or silence another device's alerts.
- Notification permission: `requestAuthorizationIfNeeded()` prompts when *any*
  profile of a battery-capable provider has an alert armed.

### Presentation

- `MenuBarPresentation.make` keeps its signature; callers now source
  `showBatteryPercent` from `store.activeProfile` (`?? false`). Its logic and
  tests are untouched.
- `PopoverView` header becomes `"\(descriptor.displayName) · \(profile.ssid or
  profile.modemIP)"` (SSID when matched by SSID, IP otherwise), replacing the
  hardcoded `"ZTE U50 · …"`. Stat-section visibility reads
  `activeProfile.stats` (falling back to defaults if `nil`, which cannot
  happen in the `.connected` branch).

### Settings UI

- **General**: a "Device" section with a provider picker over
  `ProviderKind.allCases` (only ZTE today — it establishes the pattern) and
  the detection-mode picker built from `descriptor.supportedMatchModes`.
  Changing provider clamps `matchMode` to the new descriptor's supported set
  (falling back to its default) and prefills *empty* SSID/IP fields from the
  descriptor; non-empty user values are never overwritten.
- **Panel**: `showWhenDisconnected` stays (app scope); the four stat toggles
  bind to `$settings.profile.stats` (device scope).
- **Battery**: the tab is included only when the edited profile's provider has
  `hasBattery`; its controls bind to `$settings.profile.batteryNotifications`
  and `$settings.profile.showBatteryPercent`. With ZTE only, nothing visibly
  changes.
- **Account**: UX unchanged; the footer copy can later vary by `passwordRole`.
- New `LocKey` cases (EN + PL): the device section header and the provider
  picker label. Brand names come from the descriptor and are not localized.

### File layout

One SwiftPM target; folders only.

```
Sources/ZteMenu/Modem/
  ModemData.swift        (moved; parse(_:) removed)
  ModemDriving.swift     (the driver protocol)
  ModemProfile.swift     (MatchMode + ModemProfile)
  Provider.swift         (ProviderKind, PasswordRole, ModemCapabilities,
                          ProviderDescriptor, ProviderCatalog)
  ModemMatcher.swift     (SSIDReading, CoreWLANReader, MatchResult, matcher)
Sources/ZteMenu/Providers/ZTE/
  ZTEProvider.swift      (descriptor)
  ZTEClient.swift        (ex-ModemClient + ZTE field mapping)
  ZTEAuth.swift          (moved)
Deleted:
  WiFiMonitor.swift      (dead code — only its own tests use it)
  NetworkDetector.swift  (absorbed by ModemMatcher)
Config.swift             (shrinks to refreshInterval; URL/SSID constants move
                          into the ZTE descriptor)
```

## Extensibility acceptance criterion

Adding an Asus provider must touch only:

1. `Providers/Asus/` — a driver implementing `ModemDriving` and a descriptor
   (e.g. `hasBattery: false`, `defaultMatchMode: .ipProbe`).
2. One `ProviderKind` case plus its `ProviderCatalog` entry (the exhaustive
   switch makes forgetting it a compile error).

No changes in `ModemStore`, `ModemMatcher`, presentation, or settings UI. The
battery tab, menu bar %, and notifications disappear for the Asus profile via
`hasBattery` gating that already exists.

## Testing

- `ModemMatcherTests` (absorbing `NetworkDetectorTests` and
  `WiFiMonitorTests`): SSID match, probe match, first-match-wins ordering,
  `.ssid` skipped under denied location, `ssidSkipped` reporting.
- `AppSettingsTests`: legacy payload migrates every field into one ZTE
  profile; legacy `networkMode` raw values map correctly; missing keys fall to
  defaults; empty `profiles` repairs to the default; new format round-trips.
- `ZTEClientTests`: today's `ModemClientTests` renamed — the golden request
  assertions (URLs, fields, Referer, login flow) prove the extraction changed
  no behaviour. ZTE parse tests move here from `ModemDataTests`.
- `ProviderCatalogTests`: every `ProviderKind` has a descriptor;
  `defaultMatchMode ∈ supportedMatchModes`; `supportedMatchModes` non-empty.
- `ModemStoreTests`: adapted to the profile flow; `.locationDenied` only when
  an SSID profile was skipped and nothing matched; `activeProfile` published.
- `BatteryNotifierTests`: reads the profile's config; decider resets on
  profile switch; `hasBattery == false` short-circuits; cross-profile
  `requestAuthorizationIfNeeded`.

Verification: `swift build && swift test` (currently 119 tests; no
regressions), then `./scripts/build-app.sh` and a manual smoke test: icon
appears on the ZTE network, settings round-trip, battery % toggle, popover
header shows "ZTE · <ssid>".

## Risks

- **Settings migration** is the only step that can lose user data. Mitigated
  by the tolerant per-field decoder (the codebase's existing pattern) and by
  migration tests that feed real legacy JSON payloads.
- **Driver extraction** could silently change a request. Mitigated by keeping
  `ModemClientTests`' golden assertions byte-for-byte through the rename.
- **Decider reset on profile switch** is new stateful behaviour; covered by a
  dedicated notifier test.
- The popover header changes user-visible text from "ZTE U50" to the
  provider's display name — intentional, noted for release notes.
