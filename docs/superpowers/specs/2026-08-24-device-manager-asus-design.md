# Design: Device manager and the Asus provider

Date: 2026-08-24
Status: approved

## Goal

Two things, delivered together because the second makes the first necessary:

1. **An Asus provider** — the second `ProviderKind`, proving the provider
   architecture's acceptance criterion on the user's real Asuswrt router
   (fingerprinted live: gateway `192.168.50.1`, `Server: httpd/2.0`,
   `/Main_Login.asp` login page, `appGet.cgi` redirecting to login when
   unauthenticated — the stock Asuswrt HTTP API family).
2. **A real device manager** — the settings window stops editing "the one
   profile" through fixed tabs and gains a master–detail Devices tab: multiple
   named profiles side by side (ZTE matched by SSID, Asus by IP probe), the
   matcher auto-picking whichever device the user is near. All per-device
   settings (matching, credentials, popover stats, battery) move into the
   selected device's detail view.

## Scope

In scope:

- `Providers/Asus/` — `AsusClient` driver (login + appGet + defensive parsing
  + fingerprint probe) and `AsusProvider` descriptor; `ProviderKind.asus`.
- Capability extensions: `needsUsername`, `hasRadioSignal`; descriptor's
  `makeDriver` re-signed to take the profile (it carries username + address).
- `ModemProfile` gains `name` (user label, default empty) and `username`
  (default `"admin"`); `AppSettings` gains guarded list operations
  (`addProfile`/`removeProfile`/`moveProfiles`).
- Keychain moves to per-profile slots (account = profile UUID) with a
  one-time migration of the legacy `"modem"` item — the stored ZTE password
  survives without re-entry.
- Settings window restructure: tabs become **General / Devices / Updates**.
  Panel, Battery and Account tabs are deleted; their content lives in the
  device detail. `showWhenDisconnected` (app-scoped) moves to General.
- Menu bar and popover presentation for radio-less devices: a router icon
  instead of signal bars, signal row hidden, header shows the profile name.
- EN + PL strings for everything new; removal of orphaned keys.

Out of scope:

- Per-profile history (`HistoryStore` stays global; with one battery device
  the chart stays meaningful — noted as a future item).
- Asus "extras" (client list, CPU/RAM, Traffic Analyzer monthly data) — the
  driver maps only what `ModemData` already models.
- Guest-network/AiMesh awareness, HTTPS panels, non-Asuswrt firmwares.
- App rename/release work.

## The Asuswrt driver — `Providers/Asus/`

Protocol facts (verified against the live router where possible; request
shapes follow the widely-implemented Asuswrt HTTP interface used by the
asusrouter/Home Assistant integrations):

- **Login**: `POST /login.cgi`, `Content-Type: application/x-www-form-urlencoded`,
  header `Referer: <base>/Main_Login.asp` (the firmware rejects the call
  without it), body `login_authorization=<base64("user:pass")>`. The response
  body is JSON carrying `asus_token`. Subsequent calls send it back as a
  `Cookie: asus_token=<token>` header explicitly — the driver does not depend
  on `Set-Cookie` handling, so it works with any `HTTPFetching`.
- **Data**: `GET /appGet.cgi?hook=wanlink();uptime();netdev(appobj)` with the
  token cookie. Unauthenticated calls return the login-redirect HTML instead
  of JSON (observed live) — treated as `ModemError.loginFailed`.
- A second `GET /appGet.cgi?hook=netdev(appobj)` sample after
  `speedSampleInterval` (1 s, awaited through an injected `pause` closure so
  tests run instantly) yields byte deltas → rx/tx speeds.

`AsusClient: ModemDriving` (struct, internal, `Sendable`):

```swift
struct AsusClient: ModemDriving {
    let baseURL: URL
    let username: String
    let password: String?
    let http: any HTTPFetching
    /// Injected so tests don't sleep; production defaults to Task.sleep.
    let pause: @Sendable (_ seconds: Double) async -> Void
    static let speedSampleInterval: Double = 1.0

    func fetch() async throws -> ModemData   // login → sample → pause → sample → parse
    func probe() async -> Bool               // fingerprint, see below
}
```

Mapping onto the unchanged `ModemData`:

| ModemData | Source | Notes |
| --- | --- | --- |
| `isOnline` | `wanlink_status` == 1 (or `wanlink_statusstr` "Connected") | defensive: either field |
| `networkType` | `wanlink_type` uppercased (`"DHCP"`, `"PPPOE"`, `"STATIC"`) | `networkLabel` passes unknown strings through |
| `totalRx`/`totalTx` | `netdev.INTERNET_rx`/`_tx` (hex `0x…` strings) from the second sample | counters since boot; chart layer already clamps reset-negatives |
| `rxSpeed`/`txSpeed` | (sample2 − sample1) / interval, `nil` when negative (reboot between samples) | bytes/s, same unit as ZTE |
| `sessionUptime` | digits before `" secs"` in the `uptime` hook value | |
| `batteryPercent`/`isCharging` | `nil`/`false` | no battery |
| `signalBars` | `0` | presentation never reads it for radio-less providers |
| `provider`, `rsrp`, `sinr`, session/monthly fields | `nil` | rows hide themselves |

Missing password ⇒ `ModemError.loginFailed` before any request (the popover
already localizes "check the password"). A login response without a token, or
a data response that is not JSON, also maps to `loginFailed` /
`unreachable` respectively.

**Probe = fingerprint, not reachability** (the spec'd hook finally cashed
in): `GET /Main_Login.asp` with a 3-second budget; `true` iff the body
contains `"ASUS"` (observed: `<title>ASUS Login`). A random non-Asus device
answering on the address no longer false-positives.

Descriptor:

```swift
enum AsusProvider {
    static let descriptor = ProviderDescriptor(
        displayName: "Asus",
        defaultBaseURL: URL(string: "http://192.168.50.1")!,   // Asuswrt default
        defaultSSID: "",                        // no stable factory SSID exists
        supportedMatchModes: [.ssid, .ipProbe],
        defaultMatchMode: .ipProbe,             // the original vision: Asus by IP
        capabilities: ModemCapabilities(hasBattery: false,
                                        passwordRole: .requiredForAll,
                                        needsUsername: true,
                                        hasRadioSignal: false),
        makeDriver: { profile, password, http in
            AsusClient(baseURL: profile.baseURL, username: profile.username,
                       password: password, http: http,
                       pause: { try? await Task.sleep(for: .seconds($0)) })
        }
    )
}
```

`ProviderCatalogTests` relaxes one assertion: `defaultSSID` may be empty when
`defaultMatchMode != .ssid` (a router's SSID is user-named; inventing one
would be a lie). Everything else in the catalog contract stays.

## Capability and factory changes — `Modem/Provider.swift`

```swift
struct ModemCapabilities: Sendable, Equatable {
    let hasBattery: Bool
    let passwordRole: PasswordRole
    /// Whether the device's login has a username component (Asus) or is
    /// password-only (ZTE). Drives the credentials UI.
    let needsUsername: Bool
    /// Cellular modems report bars/RSRP; a wired router has no radio to
    /// grade. Drives the menu bar symbol and the popover's signal row.
    let hasRadioSignal: Bool
}
```

`makeDriver` becomes `@Sendable (_ profile: ModemProfile, _ password: String?,
_ http: any HTTPFetching) -> any ModemDriving` — the profile carries the
address and username, so provider-specific needs stop leaking into the
signature. ZTE's closure reads `profile.baseURL` and ignores the username.
`ModemStore`'s default factory becomes:

```swift
driverFactory: { profile in
    ProviderCatalog.descriptor(for: profile.provider)
        .makeDriver(profile, Keychain.password(for: profile.id), SessionHTTP())
}
```

## Profile model — `Modem/ModemProfile.swift`

New stored properties (tolerant decode like every other field):

- `var name: String = ""` — the user's label ("Router domowy"). Empty means
  "no custom name"; every display site falls back to
  `"\(displayName) · \(identifier)"`. Migrated payloads therefore render
  exactly as before.
- `var username: String = "admin"` — used by providers with
  `needsUsername`; inert for ZTE.

`adopting(provider:)` keeps both fields untouched (a name belongs to the
user, not the brand).

`AppSettings` gains guarded list operations (pure, unit-tested; the views
never mutate `profiles` directly):

```swift
mutating func addProfile(provider: ProviderKind)          // appends makeDefault
@discardableResult
mutating func removeProfile(id: UUID) -> Bool             // refuses the last one
mutating func moveProfiles(from: IndexSet, to: Int)       // matcher priority
```

## Keychain — per-profile slots

```swift
enum Keychain {
    static func password(for profileID: UUID) -> String?
    static func setPassword(_ password: String, for profileID: UUID)
    static func deletePassword(for profileID: UUID)
    /// One-time: copies the legacy account's item into the profile's slot
    /// (only when that slot is empty), then deletes the legacy item.
    /// Idempotent; safe to call every launch.
    static func migrateLegacyPassword(from legacyAccount: String = "modem",
                                      to profileID: UUID)
}
```

Account = `profileID.uuidString`, same service. `AppDelegate` calls
`migrateLegacyPassword(to: settings.settings.profiles[0].id)` at launch —
profiles[0] is by construction the profile the 0.5 migration built from the
legacy flat settings, i.e. the device the old password belonged to.

**Test-safety note (fixes a real pre-existing bug):** the old `KeychainTests`
exercised the REAL `"modem"` slot and deleted it in `tearDown` — every test
run wiped the user's stored ZTE password. The new tests operate exclusively
on throwaway UUID slots and a caller-supplied fake `legacyAccount`, so the
suite can never touch a real credential again. The old single-slot API and
its test are deleted.

## Settings window restructure

`SettingsTab` becomes `general / devices / updates` (symbols: `gearshape`,
`wifi.router`, `arrow.triangle.2.circlepath`).
`SettingsTab.visible(for:)` is deleted — no tab is capability-gated anymore;
gating happens inside the device detail. The window widens to 560 pt to give
the master–detail room.

- **General**: launch-at-login, `showWhenDisconnected` (moved from the
  deleted Panel tab, still app-scoped), language.
- **Devices** (`Settings/DevicesSettingsTab.swift` + subviews): see below.
- **Updates**: unchanged.
- Deleted files: `PanelSettingsTab.swift`, `BatterySettingsTab.swift`,
  `AccountSettingsTab.swift` (their content is reborn inside the detail).

### Devices tab — master–detail

`SettingsView` (and its call site in `ZteMenuApp`) gains a `store:
ModemStore` parameter so the Devices tab can mark the currently matched
device.

Master (top): a `List` bound to `settings.editedProfileID` selection. Each
row: green dot when the profile is the store's `activeProfile` (matched right
now), title (`name`, fallback `brand · identifier`), subtitle with the match
rule ("SSID: ZTE_B4B622" / "IP: 192.168.50.1"), trailing provider badge
(descriptor `displayName`). Rows reorder by drag (`onMove` →
`moveProfiles`) — stored order IS matcher priority. Below the list: `+` as a
`Menu` listing `ProviderKind.allCases` by display name (append
`makeDefault`, select it), `−` with a `confirmationDialog` (disabled when
only one profile remains — the never-empty invariant stays intact).

Detail (below, for the selected profile) — one grouped `Form`:

1. **Name** — `TextField` with the fallback title as its prompt.
2. **Device type** — provider picker (writes through `adopting(provider:)`).
3. **Detection** — match-mode picker from `supportedMatchModes`, SSID or IP
   field, current-network readout (the existing CoreWLAN-at-appear pattern).
4. **Sign-in** — password `SecureField` bound to the profile's Keychain slot
   (save on focus-loss/submit/disappear, delete button — the Account tab's
   behaviour, relocated); a username `TextField` above it when
   `needsUsername`. Footer copy by `passwordRole`: `unlocksTraffic` keeps the
   existing ZTE help string; `requiredForAll` gets a new one.
5. **Popover stats** — the four `StatVisibility` toggles.
6. **Battery** — only when `hasBattery`: the menu-bar `%` toggle and the
   threshold-list editor (today's `BatterySettingsTab` rows moved verbatim
   into a subview, layout untouched).

`SettingsStore` gains UI-session selection (not persisted):

```swift
var editedProfileID: UUID?          // defaults to the first profile
var profile: ModemProfile { get set }   // now resolves the SELECTED profile,
                                        // falling back to profiles[0]
```

The existing `profile` accessor name survives, so `ModemStore`-independent
call sites keep reading naturally.

## Presentation for radio-less devices

- `MenuBarPresentation.make` gains `showsRadioSignal: Bool = true`. In the
  `.connected` branch with `showsRadioSignal == false` the symbol is
  `"wifi.router"` (no variable value, no slashed-antenna misfire from
  `signalBars == 0`); everything else (battery text, hidden/disconnected
  branches) is unchanged. `ZteMenuApp` sources the flag from the active
  profile's descriptor.
- `PopoverView`: `headerText(for:)` returns `name` when non-empty, else the
  current `"\(displayName) · \(identifier)"`; the signal row inside the basic
  stat section renders only when the profile's provider `hasRadioSignal`.

## Localization

New keys (EN / PL): `settings.tab.devices` ("Devices"/"Urządzenia"),
`settings.device.name` ("Name"/"Nazwa"), `settings.device.add` ("Add
device"/"Dodaj urządzenie"), `settings.device.remove` ("Remove
device"/"Usuń urządzenie"), `settings.device.remove_confirm` ("Remove this
device? Its settings and saved password are deleted."/PL analog),
`settings.device.active_now` ("Connected now"/"Połączone teraz"),
`settings.account.username_field` ("Username"/"Login"),
`settings.account.password_help_required` ("Required to read anything from
this device."/PL analog), `settings.signin.section` ("Sign-in"/"Logowanie").
Deleted keys: `settings.tab.panel`, `settings.tab.account`,
`settings.tab.battery`, `settings.account.section` (replaced by
`settings.signin.section`). Brand names stay unlocalized. The
completeness tests keep EN and PL in lockstep automatically.

## Extensibility acceptance criterion (recheck)

Adding a third provider still touches only `Providers/<Brand>/` + one
`ProviderKind` case + the catalog entry. The device manager itself is
provider-agnostic: the add-menu, badges, credentials and battery sections all
read the descriptor.

## Testing

- `AsusClientTests`: golden login request (URL, Referer, base64 body); token
  extraction and its echo as a `Cookie` header on appGet; hook-list request
  shape; parse fixtures (hex netdev, wanlink variants, uptime seconds);
  speed-delta arithmetic incl. negative-delta → `nil`; missing password /
  tokenless login / HTML-instead-of-JSON → `loginFailed`/`unreachable`;
  probe fingerprint true on ASUS body, false on non-ASUS and on error.
- `ProviderCatalogTests`: Asus descriptor values; relaxed defaultSSID rule;
  every-provider loop still passes; `makeDriver` builds `AsusClient` /
  `ZTEClient` from a profile.
- `ModemProfileTests`: name/username defaults + decode + `adopting` keeps
  them. `AppSettingsTests`: list-op guards (remove-last refused, move
  reorders, add appends the right provider).
- `KeychainTests` (rewritten): UUID-slot CRUD on throwaway ids; legacy
  migration from a fake legacy account (copies once, deletes source, never
  overwrites an occupied slot). No test touches the `"modem"` account.
- `MenuBarPresentationTests`: router symbol branch. `PopoverViewKeyTests`:
  header name/fallback. `SettingsTabTests`: three tabs, `visible(for:)` gone.
- `ModemStoreV2Tests`: unchanged semantics (factory is injected); one new
  assertion that the default factory type-checks is implicit via build.

Verification: full suite green, `./scripts/build-app.sh`, then a LIVE check
on the user's Asus (user enters router credentials in the new Sign-in
section): device auto-matched by IP probe, header shows the profile name,
uptime/total-transfer/speeds populate, battery UI absent; ZTE profile still
intact with its migrated password.

## Risks

- **Asuswrt response variance** across firmware versions: parsing is
  defensive (every field optional, unknowns → `nil`), the live check is the
  final arbiter, and `probe()`'s fingerprint keeps false matches out.
- **Keychain migration** touches the real legacy item: copy-then-delete,
  never overwriting an occupied destination, idempotent across launches.
- **Settings window rebuild** is the largest UI diff so far; the plan keeps
  the battery-threshold rows and the password-field behaviour as verbatim
  relocations to minimize regression surface.
- Two-sample speed measurement adds ~1 s to each Asus refresh — off-main,
  invisible to the user, bounded by the injected interval.
