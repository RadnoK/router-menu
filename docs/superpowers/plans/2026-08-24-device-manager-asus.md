# Device Manager + Asus Provider Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add the Asus (Asuswrt) provider as the second `ProviderKind`, and replace the fixed per-device settings tabs with a master–detail Devices manager so multiple named profiles (ZTE by SSID, Asus by IP probe) coexist with per-profile credentials.

**Architecture:** The provider layer is extended, not reshaped: capabilities gain `needsUsername`/`hasRadioSignal`, `makeDriver` takes the profile, and `AsusClient` implements `ModemDriving` over the Asuswrt `login.cgi`/`appGet.cgi` HTTP interface with a fingerprint `probe()`. Profiles gain `name`/`username` and guarded list operations; Keychain moves to per-profile UUID slots with a one-time legacy migration. The settings window becomes General / Devices / Updates, with all per-device UI inside the selected device's detail form.

**Tech Stack:** Swift 6, SwiftUI, SwiftPM (no Xcode project), XCTest, Security (Keychain), Foundation JSON.

**Spec:** `docs/superpowers/specs/2026-08-24-device-manager-asus-design.md`

## Global Constraints

- Work directly on `main`; APPEND-ONLY git (never reset/amend/rebase/push); check `git log --oneline -1` before each commit; parallel sessions may share the checkout.
- English code/comments/commits, style `type(scope): summary`. TDD every task (RED → GREEN); full suite green before every commit; verify DELTAS, not totals (baseline at plan time: **151 tests, 0 failures**).
- ZTE driver behaviour stays frozen (golden request tests untouched). `ModemData`, `BatteryNotificationSettings`, `BatteryAlertDecider`, `ModemMatcher`, `HistoryStore` are NOT modified by this plan.
- New types internal; tests use `@testable import ZteMenu`.
- Keychain service stays `io.8lines.zte-menu`. **No test may ever touch the real `"modem"` account or any non-throwaway slot.**
- Brand names ("ZTE", "Asus") are never localized; every other new user-facing string gets a `LocKey` case plus `en` and `pl` entries (the L10n completeness tests enforce both tables).
- The `profiles` never-empty invariant holds everywhere (`removeProfile` refuses the last one).
- Asuswrt firmware variance is expected: every parsed field is optional and unknown shapes degrade to `nil`/`false`, never crash.

## File Map (end state)

```
Sources/ZteMenu/Modem/ModemProfile.swift     +name, +username, +displayTitle
Sources/ZteMenu/Modem/Provider.swift         capabilities +2 fields; makeDriver re-signed
Sources/ZteMenu/AppSettings.swift            +addProfile/removeProfile/moveProfiles
Sources/ZteMenu/Keychain.swift               per-UUID slots + legacy migration (old API deleted)
Sources/ZteMenu/AppDelegate.swift            +1 migration call
Sources/ZteMenu/ModemStore.swift             default factory: profile + per-profile password
Sources/ZteMenu/MenuBarPresentation.swift    +showsRadioSignal param, router symbol
Sources/ZteMenu/ZteMenuApp.swift             radio flag + store into SettingsView
Sources/ZteMenu/PopoverView.swift            header via displayTitle; signal row gated
Sources/ZteMenu/SettingsStore.swift          +editedProfileID; profile accessor retargeted
Sources/ZteMenu/Settings/SettingsTab.swift   3 cases; visible(for:) deleted
Sources/ZteMenu/SettingsView.swift           3 tabs, +store param, width 560
Sources/ZteMenu/Settings/GeneralSettingsTab.swift  autostart + showWhenDisconnected + language
Sources/ZteMenu/Settings/DevicesSettingsTab.swift  NEW master list + add/remove/reorder
Sources/ZteMenu/Settings/DeviceDetailView.swift    NEW detail form (name/type/detection/stats)
Sources/ZteMenu/Settings/DeviceSignInSection.swift NEW per-profile credentials section
Sources/ZteMenu/Settings/DeviceBatterySection.swift NEW battery %+thresholds (rows verbatim)
Sources/ZteMenu/Providers/Asus/AsusClient.swift    NEW driver
Sources/ZteMenu/Providers/Asus/AsusProvider.swift  NEW descriptor
Sources/ZteMenu/Localization/LocKey.swift    +9 keys, −4 keys
Resources/en.lproj/Localizable.strings       ditto
Resources/pl.lproj/Localizable.strings       ditto
DELETED: Settings/PanelSettingsTab.swift, Settings/BatterySettingsTab.swift,
         Settings/AccountSettingsTab.swift
```

---

### Task 1: Profile fields (`name`, `username`) and guarded list operations

**Files:**
- Modify: `Sources/ZteMenu/Modem/ModemProfile.swift`
- Modify: `Sources/ZteMenu/AppSettings.swift` (add one extension; nothing else)
- Modify: `Tests/ZteMenuTests/ModemProfileTests.swift` (append)
- Test: `Tests/ZteMenuTests/AppSettingsProfileOpsTests.swift` (new)

**Interfaces:**
- Produces: `ModemProfile.name: String` (default `""`), `ModemProfile.username: String` (default `"admin"`), both tolerant-decoded and preserved by `adopting(provider:)`; `AppSettings.addProfile(provider:) -> UUID`, `AppSettings.removeProfile(id:) -> Bool` (refuses the last), `AppSettings.moveProfiles(fromOffsets:toOffset:)`.
- Consumes: `ModemProfile.makeDefault(provider:)`, existing decode style.

- [ ] **Step 1: Write the failing tests.** Append to `Tests/ZteMenuTests/ModemProfileTests.swift`:

```swift
    func testNameAndUsernameDefaults() {
        let p = ModemProfile.makeDefault(provider: .zte)
        XCTAssertEqual(p.name, "", "no custom name until the user types one")
        XCTAssertEqual(p.username, "admin")
    }

    func testNameAndUsernameSurviveCodableAndAdopting() throws {
        var p = ModemProfile.makeDefault(provider: .zte)
        p.name = "Modem w plecaku"
        p.username = "root"
        let decoded = try JSONDecoder().decode(ModemProfile.self,
                                               from: try JSONEncoder().encode(p))
        XCTAssertEqual(decoded.name, "Modem w plecaku")
        XCTAssertEqual(decoded.username, "root")
        let adopted = p.adopting(provider: .zte)
        XCTAssertEqual(adopted.name, "Modem w plecaku", "a name belongs to the user, not the brand")
        XCTAssertEqual(adopted.username, "root")
    }

    func testLegacyPayloadWithoutNewFieldsDecodesToDefaults() throws {
        let p = try JSONDecoder().decode(ModemProfile.self, from: Data("{}".utf8))
        XCTAssertEqual(p.name, "")
        XCTAssertEqual(p.username, "admin")
    }
```

Create `Tests/ZteMenuTests/AppSettingsProfileOpsTests.swift`:

```swift
import XCTest
@testable import ZteMenu

final class AppSettingsProfileOpsTests: XCTestCase {
    func testAddProfileAppendsTheRequestedProviderAndReturnsItsId() {
        var s = AppSettings()
        let id = s.addProfile(provider: .zte)
        XCTAssertEqual(s.profiles.count, 2)
        XCTAssertEqual(s.profiles.last?.id, id)
        XCTAssertEqual(s.profiles.last?.provider, .zte)
    }

    func testRemoveProfileRefusesTheLastOne() {
        var s = AppSettings()
        XCTAssertFalse(s.removeProfile(id: s.profiles[0].id))
        XCTAssertEqual(s.profiles.count, 1, "the never-empty invariant holds")
    }

    func testRemoveProfileRemovesByIdWhenOthersRemain() {
        var s = AppSettings()
        let added = s.addProfile(provider: .zte)
        XCTAssertTrue(s.removeProfile(id: s.profiles[0].id))
        XCTAssertEqual(s.profiles.map(\.id), [added])
    }

    func testRemoveProfileWithUnknownIdChangesNothing() {
        var s = AppSettings()
        _ = s.addProfile(provider: .zte)
        XCTAssertFalse(s.removeProfile(id: UUID()))
        XCTAssertEqual(s.profiles.count, 2)
    }

    func testMoveProfilesReordersMatcherPriority() {
        var s = AppSettings()
        let second = s.addProfile(provider: .zte)
        s.moveProfiles(fromOffsets: IndexSet(integer: 1), toOffset: 0)
        XCTAssertEqual(s.profiles.first?.id, second)
    }
}
```

- [ ] **Step 2: Run to verify failure**

Run: `swift test --filter "ModemProfileTests|AppSettingsProfileOpsTests" 2>&1 | tail -5`
Expected: COMPILE ERROR — no member `name` / `addProfile`.

- [ ] **Step 3: Implement.** In `Sources/ZteMenu/Modem/ModemProfile.swift`:

Add two stored properties after `modemIP` (keep declaration order stable — it drives the memberwise-style init below):

```swift
    /// The user's label ("Router domowy"). Empty means "no custom name";
    /// display sites fall back to "<brand> · <identifier>".
    var name: String
    /// The panel login for providers whose auth has a username component
    /// (Asus). Inert for password-only providers (ZTE).
    var username: String
```

Extend the designated init's parameter list (new params after `modemIP`, before `showBatteryPercent`):

```swift
         name: String = "",
         username: String = "admin",
```

with the matching assignments `self.name = name` / `self.username = username` in declaration order.

In `init(from decoder:)` add, after the `modemIP` line:

```swift
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        username = try c.decodeIfPresent(String.self, forKey: .username) ?? "admin"
```

(`adopting(provider:)` needs no change — it copies `self` and never touches either field; the test proves it.)

In `Sources/ZteMenu/AppSettings.swift`, append at file end:

```swift
// MARK: - Profile list operations

/// The only mutation paths for the profile list; views never index into
/// `profiles` directly. Stored order is matcher priority (first match wins).
extension AppSettings {
    /// Appends a fresh descriptor-prefilled profile; returns its id so the
    /// UI can select it.
    mutating func addProfile(provider: ProviderKind) -> UUID {
        let profile = ModemProfile.makeDefault(provider: provider)
        profiles.append(profile)
        return profile.id
    }

    /// Refuses to delete the last profile — the never-empty invariant that
    /// the decoder repairs is also enforced at the mutation edge.
    @discardableResult
    mutating func removeProfile(id: UUID) -> Bool {
        guard profiles.count > 1,
              let index = profiles.firstIndex(where: { $0.id == id }) else { return false }
        profiles.remove(at: index)
        return true
    }

    mutating func moveProfiles(fromOffsets: IndexSet, toOffset: Int) {
        profiles.move(fromOffsets: fromOffsets, toOffset: toOffset)
    }
}
```

- [ ] **Step 4: Run the full suite**

Run: `swift test 2>&1 | tail -3`
Expected: PASS, 0 failures — delta: +8 (3 profile + 5 ops).

- [ ] **Step 5: Commit**

```bash
git add -A && git commit -m "feat(modem): profile names, usernames and guarded list operations"
```

---

### Task 2: Keychain per-profile slots with legacy migration

The old single-slot API (`password()`, `setPassword(_:)`, `deletePassword()`) is deleted; its one production caller (`ModemStore`'s default factory line) switches to the per-profile call in the same commit. The old `KeychainTests` — which wrote to and deleted the user's REAL `"modem"` item — is replaced by tests that only ever touch throwaway UUID slots and a fake legacy account.

**Files:**
- Modify: `Sources/ZteMenu/Keychain.swift` (rewrite)
- Modify: `Sources/ZteMenu/ModemStore.swift` (one line in the default factory)
- Modify: `Sources/ZteMenu/AppDelegate.swift` (one migration call)
- Modify: `Tests/ZteMenuTests/KeychainTests.swift` (rewrite)

**Interfaces:**
- Produces: `Keychain.password(for: UUID) -> String?`, `Keychain.setPassword(_:for: UUID)`, `Keychain.deletePassword(for: UUID)`, `Keychain.migrateLegacyPassword(from: String = "modem", to: UUID)` (idempotent; copies only into an empty slot, then deletes the source).
- Consumes: `SettingsStore.settings.profiles[0].id` (the profile the 0.5 migration built from legacy flat settings — the device the old password belongs to).

- [ ] **Step 1: Rewrite the tests.** Replace `Tests/ZteMenuTests/KeychainTests.swift` with:

```swift
import XCTest
@testable import ZteMenu

/// Every slot these tests touch is a throwaway UUID (or the fake legacy
/// account below) — the suite must never read or write a real credential.
final class KeychainTests: XCTestCase {
    private let fakeLegacy = "test-legacy-\(UUID().uuidString)"
    private var ids: [UUID] = []

    private func freshID() -> UUID {
        let id = UUID()
        ids.append(id)
        return id
    }

    override func tearDown() {
        for id in ids { Keychain.deletePassword(for: id) }
        Keychain.deleteItem(account: fakeLegacy)
        super.tearDown()
    }

    func testSetGetDeletePerProfile() {
        let id = freshID()
        XCTAssertNil(Keychain.password(for: id))
        Keychain.setPassword("tajne", for: id)
        XCTAssertEqual(Keychain.password(for: id), "tajne")
        Keychain.setPassword("nowe", for: id)
        XCTAssertEqual(Keychain.password(for: id), "nowe")
        Keychain.deletePassword(for: id)
        XCTAssertNil(Keychain.password(for: id))
    }

    func testSlotsAreIndependent() {
        let a = freshID(), b = freshID()
        Keychain.setPassword("a", for: a)
        Keychain.setPassword("b", for: b)
        XCTAssertEqual(Keychain.password(for: a), "a")
        XCTAssertEqual(Keychain.password(for: b), "b")
    }

    func testLegacyMigrationCopiesOnceAndDeletesTheSource() {
        let id = freshID()
        Keychain.setItem("stare-haslo", account: fakeLegacy)
        Keychain.migrateLegacyPassword(from: fakeLegacy, to: id)
        XCTAssertEqual(Keychain.password(for: id), "stare-haslo")
        XCTAssertNil(Keychain.item(account: fakeLegacy), "the source item is gone")
        // Idempotent: a second call with nothing to migrate changes nothing.
        Keychain.migrateLegacyPassword(from: fakeLegacy, to: id)
        XCTAssertEqual(Keychain.password(for: id), "stare-haslo")
    }

    func testLegacyMigrationNeverOverwritesAnOccupiedSlot() {
        let id = freshID()
        Keychain.setPassword("juz-ustawione", for: id)
        Keychain.setItem("stare-haslo", account: fakeLegacy)
        Keychain.migrateLegacyPassword(from: fakeLegacy, to: id)
        XCTAssertEqual(Keychain.password(for: id), "juz-ustawione")
        XCTAssertNil(Keychain.item(account: fakeLegacy),
                     "the legacy item is still retired so migration stays one-shot")
    }
}
```

- [ ] **Step 2: Run to verify failure**

Run: `swift test --filter KeychainTests 2>&1 | tail -5`
Expected: COMPILE ERROR — no `password(for:)` / `setItem`.

- [ ] **Step 3: Rewrite `Sources/ZteMenu/Keychain.swift`:**

```swift
import Foundation
import Security

/// Generic-password storage, one slot per device profile (account = the
/// profile's UUID). The pre-device-manager app used a single "modem"
/// account; `migrateLegacyPassword` retires it on first launch.
enum Keychain {
    private static let service = "io.8lines.zte-menu"

    // MARK: Per-profile API

    static func password(for profileID: UUID) -> String? {
        item(account: profileID.uuidString)
    }

    static func setPassword(_ password: String, for profileID: UUID) {
        setItem(password, account: profileID.uuidString)
    }

    static func deletePassword(for profileID: UUID) {
        deleteItem(account: profileID.uuidString)
    }

    /// Copies the legacy single-slot item into the profile's slot — only
    /// when that slot is empty — then deletes the legacy item. Idempotent,
    /// safe to call every launch.
    static func migrateLegacyPassword(from legacyAccount: String = "modem",
                                      to profileID: UUID) {
        guard let legacy = item(account: legacyAccount) else { return }
        if password(for: profileID) == nil {
            setPassword(legacy, for: profileID)
        }
        deleteItem(account: legacyAccount)
    }

    // MARK: Raw item access (internal so tests can stage a fake legacy slot)

    static func item(account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data,
              let string = String(data: data, encoding: .utf8) else {
            return nil
        }
        return string
    }

    static func setItem(_ value: String, account: String) {
        deleteItem(account: account)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: Data(value.utf8),
        ]
        SecItemAdd(query as CFDictionary, nil)
    }

    static func deleteItem(account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
    }

    // MARK: Transitional single-slot API — DELETED in Task 8 together with
    // AccountSettingsTab, its last caller. Reads the legacy "modem" account,
    // which the launch migration empties; mid-plan the old Account tab may
    // therefore show an empty field. Harmless and short-lived.
    static func password() -> String? { item(account: "modem") }
    static func setPassword(_ password: String) { setItem(password, account: "modem") }
    static func deletePassword() { deleteItem(account: "modem") }
}
```

- [ ] **Step 4: Retarget the two callers.** In `Sources/ZteMenu/ModemStore.swift`, the default `driverFactory` line changes from `Keychain.password()` to:

```swift
                 .makeDriver(profile.baseURL, Keychain.password(for: profile.id), SessionHTTP())
```

In `Sources/ZteMenu/AppDelegate.swift`, inside `applicationDidFinishLaunching`, after `l10n.setLanguage(...)` add:

```swift
        // One-time: the pre-device-manager app kept a single password slot.
        // profiles[0] is the profile the settings migration built from those
        // same legacy settings, so the password belongs to it.
        Keychain.migrateLegacyPassword(to: settings.settings.profiles[0].id)
```

- [ ] **Step 5: Run the full suite**

Run: `swift test 2>&1 | tail -3`
Expected: PASS, 0 failures — delta: +3 (4 new keychain tests replace the old 1).

- [ ] **Step 6: Commit**

```bash
git add -A && git commit -m "feat(keychain): per-profile password slots with legacy migration"
```

---

### Task 3: Capability extensions and the profile-based driver factory

**Files:**
- Modify: `Sources/ZteMenu/Modem/Provider.swift`
- Modify: `Sources/ZteMenu/Providers/ZTE/ZTEProvider.swift`
- Modify: `Sources/ZteMenu/ModemStore.swift` (default factory call)
- Modify: `Tests/ZteMenuTests/ProviderCatalogTests.swift`

**Interfaces:**
- Produces: `ModemCapabilities` gains `needsUsername: Bool` and `hasRadioSignal: Bool`; `ProviderDescriptor.makeDriver: @Sendable (_ profile: ModemProfile, _ password: String?, _ http: any HTTPFetching) -> any ModemDriving`; relaxed catalog rule: `defaultSSID` may be empty when `defaultMatchMode != .ssid`.
- Consumes: `ModemProfile.baseURL`, `ModemProfile.username` (Task 1), `Keychain.password(for:)` (Task 2).

- [ ] **Step 1: Update the tests.** In `Tests/ZteMenuTests/ProviderCatalogTests.swift`:

Replace the defaultSSID assertion inside `testEveryProviderHasACoherentDescriptor` with:

```swift
            if d.defaultMatchMode == .ssid {
                XCTAssertFalse(d.defaultSSID.isEmpty,
                               "\(kind) matches by SSID by default but ships no default SSID")
            }
```

In `testZTEDescriptorMatchesTheU50`, extend the capability asserts:

```swift
        XCTAssertFalse(d.capabilities.needsUsername)
        XCTAssertTrue(d.capabilities.hasRadioSignal)
```

Replace `testZTEFactoryBuildsAZTEDriver` with:

```swift
    func testZTEFactoryBuildsAZTEDriverFromAProfile() {
        var profile = ModemProfile.makeDefault(provider: .zte)
        profile.modemIP = "10.0.0.1"
        let d = ProviderCatalog.descriptor(for: .zte)
        let driver = d.makeDriver(profile, "secret", URLSession.shared)
        XCTAssertTrue(driver is ZTEClient)
    }
```

- [ ] **Step 2: Run to verify failure**

Run: `swift test --filter ProviderCatalogTests 2>&1 | tail -5`
Expected: COMPILE ERROR — no `needsUsername`; factory arity mismatch.

- [ ] **Step 3: Implement.** In `Sources/ZteMenu/Modem/Provider.swift`, `ModemCapabilities` becomes:

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

and the factory in `ProviderDescriptor` becomes:

```swift
    let makeDriver: @Sendable (_ profile: ModemProfile, _ password: String?, _ http: any HTTPFetching) -> any ModemDriving
```

In `Sources/ZteMenu/Providers/ZTE/ZTEProvider.swift`:

```swift
        capabilities: ModemCapabilities(hasBattery: true,
                                        passwordRole: .unlocksTraffic,
                                        needsUsername: false,
                                        hasRadioSignal: true),
        makeDriver: { profile, password, http in
            ZTEClient(baseURL: profile.baseURL, http: http, password: password)
        }
```

In `Sources/ZteMenu/ModemStore.swift`, the default factory body becomes:

```swift
         driverFactory: @escaping @MainActor (ModemProfile) -> any ModemDriving = { profile in
             ProviderCatalog.descriptor(for: profile.provider)
                 .makeDriver(profile, Keychain.password(for: profile.id), SessionHTTP())
         }
```

- [ ] **Step 4: Run the full suite**

Run: `swift test 2>&1 | tail -3`
Expected: PASS, 0 failures — delta: ±0 (assertions changed in place).

- [ ] **Step 5: Commit**

```bash
git add -A && git commit -m "feat(modem): username/radio capabilities and a profile-based driver factory"
```

---

### Task 4: The Asuswrt driver — `AsusClient`

**Files:**
- Create: `Sources/ZteMenu/Providers/Asus/AsusClient.swift`
- Test: `Tests/ZteMenuTests/AsusClientTests.swift` (new)

**Interfaces:**
- Produces: `struct AsusClient: ModemDriving` with `init(baseURL: URL, username: String, password: String?, http: any HTTPFetching, pause: @escaping @Sendable (Double) async -> Void = { try? await Task.sleep(for: .seconds($0)) })`, `static let speedSampleInterval: Double = 1.0`, `static func parse(first: [String: Any], second: [String: Any], interval: Double) -> ModemData` (internal for tests).
- Consumes: `ModemDriving`, `ModemError`, `ModemData` memberwise init, `HTTPFetching` (all existing).

- [ ] **Step 1: Write the failing tests.** Create `Tests/ZteMenuTests/AsusClientTests.swift`:

```swift
import XCTest
@testable import ZteMenu

/// Records every request and replays canned responses in order.
private final class SequenceHTTP: HTTPFetching, @unchecked Sendable {
    private let responses: [Data]
    private(set) var requests: [URLRequest] = []
    private var i = 0
    init(_ responses: [String]) { self.responses = responses.map { Data($0.utf8) } }
    func data(for request: URLRequest) async throws -> Data {
        requests.append(request)
        defer { i += 1 }
        return responses[min(i, responses.count - 1)]
    }
}

private struct ThrowingHTTP: HTTPFetching {
    struct Boom: Error {}
    func data(for request: URLRequest) async throws -> Data { throw Boom() }
}

private let asusURL = URL(string: "http://192.168.50.1")!
private let loginOK = #"{"asus_token":"AbCdEf123456"}"#
private let dataOK = #"""
{"wan0_state_t":"2","wan0_proto":"dhcp",
 "uptime":"Mon, 24 Aug 2026 21:40:12 +0200(1234567 secs since boot)",
 "netdev":{"INTERNET_rx":"0x0000000000001000","INTERNET_tx":"0x0000000000000800"}}
"""#
private let dataSecond = #"{"netdev":{"INTERNET_rx":"0x0000000000002000","INTERNET_tx":"0x0000000000000C00"}}"#

private func makeClient(_ http: any HTTPFetching, password: String? = "haslo") -> AsusClient {
    AsusClient(baseURL: asusURL, username: "admin", password: password,
               http: http, pause: { _ in })   // tests never sleep
}

final class AsusClientLoginTests: XCTestCase {
    func testLoginRequestShape() async throws {
        let http = SequenceHTTP([loginOK, dataOK, dataSecond])
        _ = try await makeClient(http).fetch()

        let login = http.requests[0]
        XCTAssertEqual(login.url?.absoluteString, "http://192.168.50.1/login.cgi")
        XCTAssertEqual(login.httpMethod, "POST")
        XCTAssertEqual(login.value(forHTTPHeaderField: "Referer"),
                       "http://192.168.50.1/Main_Login.asp")
        XCTAssertEqual(login.value(forHTTPHeaderField: "Content-Type"),
                       "application/x-www-form-urlencoded")
        let body = String(data: login.httpBody ?? Data(), encoding: .utf8) ?? ""
        // base64("admin:haslo") — the credential pair, never logged elsewhere.
        XCTAssertEqual(body, "login_authorization=YWRtaW46aGFzbG8=")
    }

    func testTokenEchoedAsCookieOnDataRequests() async throws {
        let http = SequenceHTTP([loginOK, dataOK, dataSecond])
        _ = try await makeClient(http).fetch()

        XCTAssertEqual(http.requests.count, 3, "login + two samples")
        for request in http.requests.dropFirst() {
            XCTAssertEqual(request.value(forHTTPHeaderField: "Cookie"),
                           "asus_token=AbCdEf123456")
        }
        let hooks = http.requests[1].url?.absoluteString ?? ""
        XCTAssertTrue(hooks.hasPrefix("http://192.168.50.1/appGet.cgi?hook="))
        for hook in ["nvram_get(wan0_state_t)", "nvram_get(wan0_proto)",
                     "uptime()", "netdev(appobj)"] {
            XCTAssertTrue(hooks.contains(hook), "missing hook \(hook)")
        }
        XCTAssertTrue(http.requests[2].url!.absoluteString.contains("netdev(appobj)"))
    }

    func testMissingPasswordFailsBeforeAnyRequest() async {
        let http = SequenceHTTP([loginOK])
        do {
            _ = try await makeClient(http, password: nil).fetch()
            XCTFail("expected loginFailed")
        } catch ModemError.loginFailed {
            XCTAssertTrue(http.requests.isEmpty)
        } catch { XCTFail("unexpected \(error)") }
    }

    func testTokenlessLoginResponseIsLoginFailed() async {
        // What the firmware returns for bad credentials (an error page /
        // JSON without asus_token).
        let http = SequenceHTTP([#"{"error_status":"3"}"#])
        do {
            _ = try await makeClient(http).fetch()
            XCTFail("expected loginFailed")
        } catch ModemError.loginFailed {
        } catch { XCTFail("unexpected \(error)") }
    }

    func testHTMLInsteadOfDataIsUnreachable() async {
        // Session expired mid-flight: appGet answers with the login redirect.
        let html = "<HTML><HEAD><script>window.top.location.href='/Main_Login.asp';</script></HEAD></HTML>"
        let http = SequenceHTTP([loginOK, html])
        do {
            _ = try await makeClient(http).fetch()
            XCTFail("expected unreachable")
        } catch ModemError.loginFailed {
            XCTFail("HTML after a good login is not a credential problem")
        } catch {
            // ok — any non-login error maps to .unreachable at the store
        }
    }
}

final class AsusClientParseTests: XCTestCase {
    private func fetch(first: String = dataOK, second: String = dataSecond) async throws -> ModemData {
        let http = SequenceHTTP([loginOK, first, second])
        return try await makeClient(http).fetch()
    }

    func testMapsOnlineUptimeAndCounters() async throws {
        let d = try await fetch()
        XCTAssertTrue(d.isOnline)
        XCTAssertEqual(d.networkType, "DHCP")
        XCTAssertEqual(d.sessionUptime, 1234567)
        XCTAssertEqual(d.totalRx, 0x2000, "totals come from the fresher second sample")
        XCTAssertEqual(d.totalTx, 0xC00)
        XCTAssertNil(d.batteryPercent)
        XCTAssertFalse(d.isCharging)
        XCTAssertEqual(d.signalBars, 0)
        XCTAssertNil(d.rsrp)
        XCTAssertNil(d.monthlyRx)
    }

    func testSpeedsAreTheSampleDeltaPerSecond() async throws {
        let d = try await fetch()
        // rx: 0x2000-0x1000 = 4096 B over 1 s; tx: 0xC00-0x800 = 1024 B.
        XCTAssertEqual(d.rxSpeed, 4096)
        XCTAssertEqual(d.txSpeed, 1024)
    }

    func testCounterResetBetweenSamplesYieldsNilSpeeds() async throws {
        let rebooted = #"{"netdev":{"INTERNET_rx":"0x10","INTERNET_tx":"0x10"}}"#
        let d = try await fetch(second: rebooted)
        XCTAssertNil(d.rxSpeed)
        XCTAssertNil(d.txSpeed)
    }

    func testOfflineAndUnknownFieldsDegradeGracefully() async throws {
        let sparse = #"{"wan0_state_t":"0","netdev":{"INTERNET_rx":"junk","INTERNET_tx":"0xZZ"}}"#
        let d = try await fetch(first: sparse, second: sparse)
        XCTAssertFalse(d.isOnline)
        XCTAssertEqual(d.networkType, "")
        XCTAssertNil(d.sessionUptime)
        XCTAssertNil(d.totalRx)
        XCTAssertNil(d.rxSpeed)
    }
}

final class AsusClientProbeTests: XCTestCase {
    private final class OneShotHTTP: HTTPFetching, @unchecked Sendable {
        let payload: String
        private(set) var request: URLRequest?
        init(_ payload: String) { self.payload = payload }
        func data(for request: URLRequest) async throws -> Data {
            self.request = request
            return Data(payload.utf8)
        }
    }

    func testProbeRecognisesTheAsusLoginPage() async {
        let http = OneShotHTTP("<title>ASUS Login</title>")
        let client = makeClient(http)
        let hit = await client.probe()
        XCTAssertTrue(hit)
        XCTAssertEqual(http.request?.url?.absoluteString,
                       "http://192.168.50.1/Main_Login.asp")
        XCTAssertEqual(http.request?.timeoutInterval, 3)
    }

    func testProbeRejectsForeignDevices() async {
        let hit = await makeClient(OneShotHTTP("<title>TP-Link</title>")).probe()
        XCTAssertFalse(hit, "an answering non-Asus device must not match")
    }

    func testProbeFailsOnError() async {
        let hit = await makeClient(ThrowingHTTP()).probe()
        XCTAssertFalse(hit)
    }
}
```

- [ ] **Step 2: Run to verify failure**

Run: `swift test --filter AsusClient 2>&1 | tail -5`
Expected: COMPILE ERROR — `cannot find 'AsusClient' in scope`.

- [ ] **Step 3: Implement.** Create `Sources/ZteMenu/Providers/Asus/AsusClient.swift`:

```swift
import Foundation

/// Driver for stock Asuswrt routers (and Asuswrt-Merlin): authenticates via
/// `login.cgi` (base64 credentials → `asus_token`), then reads state through
/// `appGet.cgi` hooks. Field shapes vary between firmware builds, so every
/// parse is defensive — an unknown shape degrades to nil, never crashes.
struct AsusClient: ModemDriving {
    let baseURL: URL
    let username: String
    let password: String?
    let http: any HTTPFetching
    /// Injected so tests don't sleep; production waits between the two
    /// traffic-counter samples that yield the transfer speeds.
    let pause: @Sendable (_ seconds: Double) async -> Void

    static let speedSampleInterval: Double = 1.0

    init(baseURL: URL,
         username: String,
         password: String?,
         http: any HTTPFetching = URLSession.shared,
         pause: @escaping @Sendable (_ seconds: Double) async -> Void = { seconds in
             try? await Task.sleep(for: .seconds(seconds))
         }) {
        self.baseURL = baseURL
        self.username = username
        self.password = password
        self.http = http
        self.pause = pause
    }

    func fetch() async throws -> ModemData {
        let token = try await login()
        let first = try await appGet(
            "nvram_get(wan0_state_t);nvram_get(wan0_proto);uptime();netdev(appobj)",
            token: token)
        await pause(Self.speedSampleInterval)
        let second = try await appGet("netdev(appobj)", token: token)
        return Self.parse(first: first, second: second, interval: Self.speedSampleInterval)
    }

    /// Fingerprint, not mere reachability: only a device serving the ASUS
    /// login page counts as "this profile's router".
    func probe() async -> Bool {
        var request = URLRequest(url: baseURL.appendingPathComponent("Main_Login.asp"))
        request.timeoutInterval = 3
        guard let data = try? await http.data(for: request),
              let body = String(data: data, encoding: .utf8) else { return false }
        return body.contains("ASUS")
    }

    // MARK: Protocol steps

    private func login() async throws -> String {
        guard let password else { throw ModemError.loginFailed }
        var request = URLRequest(url: baseURL.appendingPathComponent("login.cgi"))
        request.httpMethod = "POST"
        // The firmware rejects login.cgi calls that don't come "from" its
        // own login page.
        request.setValue(baseURL.absoluteString + "/Main_Login.asp",
                         forHTTPHeaderField: "Referer")
        request.setValue("application/x-www-form-urlencoded",
                         forHTTPHeaderField: "Content-Type")
        let credentials = Data("\(username):\(password)".utf8).base64EncodedString()
        request.httpBody = Data("login_authorization=\(credentials)".utf8)
        let data = try await http.data(for: request)
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let token = object["asus_token"] as? String, !token.isEmpty else {
            throw ModemError.loginFailed
        }
        return token
    }

    private func appGet(_ hooks: String, token: String) async throws -> [String: Any] {
        var components = URLComponents(url: baseURL.appendingPathComponent("appGet.cgi"),
                                       resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "hook", value: hooks)]
        var request = URLRequest(url: components.url!)
        // Sent explicitly rather than relying on cookie storage, so the
        // driver works with any HTTPFetching.
        request.setValue("asus_token=\(token)", forHTTPHeaderField: "Cookie")
        let data = try await http.data(for: request)
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            // An expired session answers with the login-redirect HTML.
            throw ModemError.appGetNotJSON
        }
        return object
    }

    // MARK: Mapping

    /// Internal so the fixture tests can drive it directly if needed.
    static func parse(first: [String: Any], second: [String: Any],
                      interval: Double) -> ModemData {
        func hex(_ object: [String: Any], _ key: String) -> Int? {
            guard let netdev = object["netdev"] as? [String: Any],
                  let raw = netdev[key] as? String,
                  raw.lowercased().hasPrefix("0x"),
                  let value = Int(raw.dropFirst(2), radix: 16) else { return nil }
            return value
        }
        func speed(_ old: Int?, _ new: Int?) -> Int? {
            guard let old, let new, new >= old, interval > 0 else { return nil }
            return Int(Double(new - old) / interval)
        }

        let uptime: Int? = (first["uptime"] as? String).flatMap { raw in
            // "Mon, 24 Aug 2026 21:40:12 +0200(1234567 secs since boot)"
            guard let range = raw.range(of: " secs", options: []) else { return nil }
            let head = raw[..<range.lowerBound]
            let digits = head.reversed().prefix { $0.isNumber }
            guard !digits.isEmpty else { return nil }
            return Int(String(digits.reversed()))
        }

        let proto = (first["wan0_proto"] as? String) ?? ""
        return ModemData(
            batteryPercent: nil,
            isCharging: false,
            signalBars: 0,
            networkType: proto.uppercased(),
            provider: nil,
            rsrp: nil,
            sinr: nil,
            isOnline: (first["wan0_state_t"] as? String) == "2",
            rxSpeed: speed(hex(first, "INTERNET_rx"), hex(second, "INTERNET_rx")),
            txSpeed: speed(hex(first, "INTERNET_tx"), hex(second, "INTERNET_tx")),
            sessionRx: nil,
            sessionTx: nil,
            totalRx: hex(second, "INTERNET_rx"),
            totalTx: hex(second, "INTERNET_tx"),
            monthlyRx: nil,
            monthlyTx: nil,
            sessionUptime: uptime,
            monthlyUptime: nil
        )
    }
}

extension ModemError {
    /// The session died between login and appGet — surfaces as
    /// `.unreachable` in the store, which is accurate: the panel stopped
    /// answering usefully mid-conversation.
    static var appGetNotJSON: Error { NSError(domain: "AsusClient.appGet", code: 1) }
}
```

Note on the last block: `ModemError` is a two-case enum (`loginFailed`); anything that is NOT `ModemError.loginFailed` maps to `.error(.unreachable)` in `ModemStore`. The helper just makes the throw site readable — do not add a case to `ModemError`.

- [ ] **Step 4: Run the full suite**

Run: `swift test 2>&1 | tail -3`
Expected: PASS, 0 failures — delta: +12 (5 login + 4 parse + 3 probe).

- [ ] **Step 5: Commit**

```bash
git add -A && git commit -m "feat(asus): Asuswrt driver with fingerprint probe and sampled speeds"
```

---

### Task 5: `ProviderKind.asus` and the Asus descriptor

**Files:**
- Create: `Sources/ZteMenu/Providers/Asus/AsusProvider.swift`
- Modify: `Sources/ZteMenu/Modem/Provider.swift` (one case + one switch arm)
- Modify: `Tests/ZteMenuTests/ProviderCatalogTests.swift` (append)

**Interfaces:**
- Produces: `ProviderKind.asus` (raw `"asus"`, persisted); `AsusProvider.descriptor`.
- Consumes: `AsusClient` (Task 4), extended capabilities (Task 3).

- [ ] **Step 1: Write the failing tests.** Append to `ProviderCatalogTests`:

```swift
    func testAsusDescriptorMatchesAsuswrt() {
        let d = ProviderCatalog.descriptor(for: .asus)
        XCTAssertEqual(d.displayName, "Asus")
        XCTAssertEqual(d.defaultBaseURL.absoluteString, "http://192.168.50.1")
        XCTAssertEqual(d.defaultSSID, "", "no factory SSID exists for user-named networks")
        XCTAssertEqual(d.supportedMatchModes, [.ssid, .ipProbe])
        XCTAssertEqual(d.defaultMatchMode, .ipProbe)
        XCTAssertFalse(d.capabilities.hasBattery)
        XCTAssertEqual(d.capabilities.passwordRole, .requiredForAll)
        XCTAssertTrue(d.capabilities.needsUsername)
        XCTAssertFalse(d.capabilities.hasRadioSignal)
    }

    func testAsusFactoryBuildsAnAsusDriverFromAProfile() {
        let profile = ModemProfile.makeDefault(provider: .asus)
        XCTAssertEqual(profile.modemIP, "192.168.50.1")
        XCTAssertEqual(profile.matchMode, .ipProbe)
        let driver = ProviderCatalog.descriptor(for: .asus)
            .makeDriver(profile, "haslo", URLSession.shared)
        XCTAssertTrue(driver is AsusClient)
    }

    func testProviderRawValuesAreStable() {
        XCTAssertEqual(ProviderKind.zte.rawValue, "zte")
        XCTAssertEqual(ProviderKind.asus.rawValue, "asus")
    }
```

- [ ] **Step 2: Run to verify failure**

Run: `swift test --filter ProviderCatalogTests 2>&1 | tail -5`
Expected: COMPILE ERROR — no `.asus`.

- [ ] **Step 3: Implement.** In `Sources/ZteMenu/Modem/Provider.swift` add the case and the catalog arm:

```swift
enum ProviderKind: String, Codable, CaseIterable, Sendable {
    case zte
    case asus
}
```

```swift
        switch kind {
        case .zte: return ZTEProvider.descriptor
        case .asus: return AsusProvider.descriptor
        }
```

Create `Sources/ZteMenu/Providers/Asus/AsusProvider.swift`:

```swift
import Foundation

enum AsusProvider {
    static let descriptor = ProviderDescriptor(
        displayName: "Asus",
        defaultBaseURL: URL(string: "http://192.168.50.1")!,   // Asuswrt default
        defaultSSID: "",
        supportedMatchModes: [.ssid, .ipProbe],
        defaultMatchMode: .ipProbe,
        capabilities: ModemCapabilities(hasBattery: false,
                                        passwordRole: .requiredForAll,
                                        needsUsername: true,
                                        hasRadioSignal: false),
        makeDriver: { profile, password, http in
            AsusClient(baseURL: profile.baseURL,
                       username: profile.username,
                       password: password,
                       http: http)
        }
    )
}
```

- [ ] **Step 4: Run the full suite** (the every-provider catalog loop now covers Asus automatically)

Run: `swift test 2>&1 | tail -3`
Expected: PASS, 0 failures — delta: +3.

- [ ] **Step 5: Commit**

```bash
git add -A && git commit -m "feat(asus): register the Asus provider in the catalog"
```

---

### Task 6: Presentation for radio-less devices and profile display titles

**Files:**
- Modify: `Sources/ZteMenu/Modem/ModemProfile.swift` (add `displayTitle`)
- Modify: `Sources/ZteMenu/MenuBarPresentation.swift`
- Modify: `Sources/ZteMenu/ZteMenuApp.swift`
- Modify: `Sources/ZteMenu/PopoverView.swift`
- Modify: `Tests/ZteMenuTests/MenuBarPresentationTests.swift`, `Tests/ZteMenuTests/PopoverViewKeyTests.swift` (append)

**Interfaces:**
- Produces: `ModemProfile.displayTitle: String` (name, else `"<brand> · <identifier>"`); `MenuBarPresentation.make(for:showBatteryPercent:showWhenDisconnected:showsRadioSignal:)` with `showsRadioSignal: Bool = true` — connected + `false` ⇒ symbol `"wifi.router"`, `variableValue 0`, battery text rules unchanged; `PopoverView.headerText(for:)` delegates to `displayTitle`; the popover's signal row renders only for `hasRadioSignal` providers.
- Consumes: capabilities (Task 3), `store.activeProfile` (existing).

- [ ] **Step 1: Write the failing tests.** Append to `Tests/ZteMenuTests/PopoverViewKeyTests.swift`:

```swift
    func testHeaderPrefersTheCustomName() {
        var p = ModemProfile.makeDefault(provider: .asus)
        p.name = "Router domowy"
        XCTAssertEqual(PopoverView.headerText(for: p), "Router domowy")
    }

    func testHeaderFallsBackToBrandAndIdentifier() {
        var p = ModemProfile.makeDefault(provider: .asus)
        p.name = ""
        XCTAssertEqual(PopoverView.headerText(for: p), "Asus · 192.168.50.1")
    }
```

Append to `Tests/ZteMenuTests/MenuBarPresentationTests.swift` (match the file's existing test style — it builds `ModemData` via `ZTEClient.parse` or memberwise; use whichever helper the file already uses; the assertions below are the contract):

```swift
    func testConnectedRadiolessDeviceShowsTheRouterSymbol() {
        let d = ZTEClient.parse(["signalbar": "0", "network_type": "DHCP",
                                 "battery_value": ""])
        let p = MenuBarPresentation.make(for: .connected(d),
                                         showBatteryPercent: true,
                                         showWhenDisconnected: false,
                                         showsRadioSignal: false)
        XCTAssertTrue(p.isVisible)
        XCTAssertEqual(p.symbolName, "wifi.router")
        XCTAssertNil(p.batteryText, "a battery-less reading shows no percentage")
    }

    func testConnectedRadioDeviceKeepsTheExistingSymbols() {
        let d = ZTEClient.parse(["signalbar": "4", "network_type": "ENDC",
                                 "battery_value": "80"])
        let p = MenuBarPresentation.make(for: .connected(d),
                                         showBatteryPercent: true,
                                         showWhenDisconnected: false,
                                         showsRadioSignal: true)
        XCTAssertEqual(p.symbolName, "cellularbars")
        XCTAssertEqual(p.batteryText, "80%")
    }
```

- [ ] **Step 2: Run to verify failure**

Run: `swift test --filter "PopoverViewKeyTests|MenuBarPresentationTests" 2>&1 | tail -5`
Expected: COMPILE ERROR — `make` has no `showsRadioSignal`; header tests fail on `.asus` fallback? No — compile error comes first.

- [ ] **Step 3: Implement.** In `Sources/ZteMenu/Modem/ModemProfile.swift` add:

```swift
    /// What lists and headers call this device: the user's name, or the
    /// brand plus whichever identifier the profile matches by.
    var displayTitle: String {
        guard name.isEmpty else { return name }
        let brand = ProviderCatalog.descriptor(for: provider).displayName
        let identifier = matchMode == .ssid ? ssid : modemIP
        return "\(brand) · \(identifier)"
    }
```

In `Sources/ZteMenu/PopoverView.swift`, `headerText(for:)` becomes:

```swift
    static func headerText(for profile: ModemProfile) -> String {
        profile.displayTitle
    }
```

and inside `statSection(_:)` gate the signal row (the builder already receives the profile via `connected(_:profile:)` — pass it down: change `statSection(d)` call to `statSection(d, profile: profile)` and the builder signature accordingly):

```swift
    @ViewBuilder
    private func statSection(_ d: ModemData, profile: ModemProfile) -> some View {
        if let b = d.batteryPercent {
            row(batterySymbol(b, d.isCharging), l10n(.popoverBattery),
                "\(b)%\(d.isCharging ? " ⚡" : "")")
        }
        if ProviderCatalog.descriptor(for: profile.provider).capabilities.hasRadioSignal {
            row("cellularbars", l10n(.popoverSignal),
                "\(l10n(Self.key(for: d.signalQuality))) (\(d.signalBars)/5)")
        }
        row("antenna.radiowaves.left.and.right", l10n(.popoverNetwork), d.networkLabel)
    }
```

In `Sources/ZteMenu/MenuBarPresentation.swift`, add the parameter and the branch:

```swift
    static func make(for state: AppState,
                     showBatteryPercent: Bool = false,
                     showWhenDisconnected: Bool = false,
                     showsRadioSignal: Bool = true) -> MenuBarPresentation {
```

and in the `.connected(let d)` case, FIRST:

```swift
        case .connected(let d):
            guard showsRadioSignal else {
                // A wired router has no bars to grade — a healthy connection
                // shows the router symbol, full stop.
                return presentation(symbolName: "wifi.router",
                                    variableValue: 0,
                                    battery: d.batteryPercent)
            }
            if d.signalBars <= 0 {
```

(the existing two sub-branches stay under the `guard`).

In `Sources/ZteMenu/ZteMenuApp.swift`, extend the presentation wiring:

```swift
        let activeProfile = settings.settings.profile(with: appDelegate.store.activeProfile?.id)
            ?? appDelegate.store.activeProfile
        let showsRadioSignal = activeProfile
            .map { ProviderCatalog.descriptor(for: $0.provider).capabilities.hasRadioSignal }
            ?? true
        let p = MenuBarPresentation.make(for: store.state,
                                         showBatteryPercent: activeProfile?.showBatteryPercent ?? false,
                                         showWhenDisconnected: settings.settings.showWhenDisconnected,
                                         showsRadioSignal: showsRadioSignal)
```

- [ ] **Step 4: Run the full suite** (the two Task-8-era header tests keep passing — the fallback path is unchanged)

Run: `swift test 2>&1 | tail -3`
Expected: PASS, 0 failures — delta: +4.

- [ ] **Step 5: Commit**

```bash
git add -A && git commit -m "feat(menubar): router symbol and profile display titles for radio-less devices"
```

---

### Task 7: Device manager views and the edited-profile selection

New files only (plus `SettingsStore` and localization). Nothing references the new views yet — Task 8 wires them into the window. The battery threshold rows move VERBATIM from `BatterySettingsTab` (layout untouched); the password-field behaviour moves from `AccountSettingsTab` adapted to per-profile slots.

**Files:**
- Modify: `Sources/ZteMenu/SettingsStore.swift`
- Create: `Sources/ZteMenu/Settings/DevicesSettingsTab.swift`
- Create: `Sources/ZteMenu/Settings/DeviceDetailView.swift`
- Create: `Sources/ZteMenu/Settings/DeviceSignInSection.swift`
- Create: `Sources/ZteMenu/Settings/DeviceBatterySection.swift`
- Modify: `Sources/ZteMenu/Localization/LocKey.swift`, `Resources/en.lproj/Localizable.strings`, `Resources/pl.lproj/Localizable.strings`
- Modify: `Tests/ZteMenuTests/SettingsStoreTests.swift` (append)

**Interfaces:**
- Produces: `SettingsStore.editedProfileID: UUID?`; `SettingsStore.profile` resolves the selected profile (fallback `profiles[0]`), setter writes back BY ID; the four view types; LocKeys `settingsTabDevices ("settings.tab.devices")`, `settingsDeviceName ("settings.device.name")`, `settingsDeviceAdd ("settings.device.add")`, `settingsDeviceRemove ("settings.device.remove")`, `settingsDeviceRemoveConfirm ("settings.device.remove_confirm")`, `settingsDeviceActiveNow ("settings.device.active_now")`, `settingsUsernameField ("settings.account.username_field")`, `settingsSignInSection ("settings.signin.section")`, `settingsPasswordHelpRequired ("settings.account.password_help_required")`.
- Consumes: profile ops (Task 1), per-profile Keychain (Task 2), capabilities (Task 3), `displayTitle` (Task 6), `store.activeProfile` (existing).

- [ ] **Step 1: Write the failing tests.** Append to `Tests/ZteMenuTests/SettingsStoreTests.swift`:

```swift
    func testProfileAccessorFollowsTheSelection() {
        let store = SettingsStore(defaults: freshDefaults())
        let secondID = store.settings.addProfile(provider: .asus)
        XCTAssertEqual(store.profile.provider, .zte, "nil selection falls back to the first profile")

        store.editedProfileID = secondID
        XCTAssertEqual(store.profile.provider, .asus)

        store.profile.name = "Router"
        XCTAssertEqual(store.settings.profiles[1].name, "Router",
                       "the setter writes back to the SELECTED profile by id")
        XCTAssertEqual(store.settings.profiles[0].name, "")
    }

    func testStaleSelectionFallsBackToTheFirstProfile() {
        let store = SettingsStore(defaults: freshDefaults())
        store.editedProfileID = UUID()
        XCTAssertEqual(store.profile.id, store.settings.profiles[0].id)
    }
```

- [ ] **Step 2: Run to verify failure**

Run: `swift test --filter SettingsStoreTests 2>&1 | tail -5`
Expected: COMPILE ERROR — no `editedProfileID`.

- [ ] **Step 3: Extend `SettingsStore`.** In `Sources/ZteMenu/SettingsStore.swift`, replace the `profile` accessor with:

```swift
    /// Which profile the settings window is editing. UI-session state, not
    /// persisted; nil (or a deleted id) falls back to the first profile.
    var editedProfileID: UUID?

    var profile: ModemProfile {
        get {
            settings.profiles.first { $0.id == editedProfileID } ?? settings.profiles[0]
        }
        set {
            guard let index = settings.profiles.firstIndex(where: { $0.id == newValue.id })
            else { return }
            settings.profiles[index] = newValue
        }
    }
```

- [ ] **Step 4: Localization.** In `Sources/ZteMenu/Localization/LocKey.swift`, after the `settingsDeviceType` case add:

```swift
    // Settings — device manager
    case settingsTabDevices = "settings.tab.devices"
    case settingsDeviceName = "settings.device.name"
    case settingsDeviceAdd = "settings.device.add"
    case settingsDeviceRemove = "settings.device.remove"
    case settingsDeviceRemoveConfirm = "settings.device.remove_confirm"
    case settingsDeviceActiveNow = "settings.device.active_now"
    case settingsUsernameField = "settings.account.username_field"
    case settingsSignInSection = "settings.signin.section"
    case settingsPasswordHelpRequired = "settings.account.password_help_required"
```

`Resources/en.lproj/Localizable.strings` — add below the network block:

```
/* Settings — device manager */
"settings.tab.devices" = "Devices";
"settings.device.name" = "Name";
"settings.device.add" = "Add device";
"settings.device.remove" = "Remove device";
"settings.device.remove_confirm" = "Remove this device? Its settings and saved password are deleted.";
"settings.device.active_now" = "Connected now";
"settings.account.username_field" = "Username";
"settings.signin.section" = "Sign-in";
"settings.account.password_help_required" = "Required to read anything from this device.";
```

`Resources/pl.lproj/Localizable.strings` — same block:

```
/* Ustawienia — menedżer urządzeń */
"settings.tab.devices" = "Urządzenia";
"settings.device.name" = "Nazwa";
"settings.device.add" = "Dodaj urządzenie";
"settings.device.remove" = "Usuń urządzenie";
"settings.device.remove_confirm" = "Usunąć to urządzenie? Jego ustawienia i zapisane hasło zostaną skasowane.";
"settings.device.active_now" = "Połączone teraz";
"settings.account.username_field" = "Login";
"settings.signin.section" = "Logowanie";
"settings.account.password_help_required" = "Wymagane, aby cokolwiek odczytać z tego urządzenia.";
```

- [ ] **Step 5: Create the views.**

`Sources/ZteMenu/Settings/DeviceBatterySection.swift` — the menu-bar `%` toggle plus the threshold editor. The `thresholdRow(_:)` body and the add/remove/full-charge sections are MOVED VERBATIM from today's `BatterySettingsTab.swift` (same bindings via `settings.profile...`, same `.firstTextBaseline` layout, same comments); only the type wrapper changes:

```swift
import SwiftUI

/// Battery percentage in the menu bar, and the alerts fired as the battery
/// drains — shown only for providers whose devices have a battery.
struct DeviceBatterySection: View {
    @Bindable var settings: SettingsStore
    let l10n: L10n
    // Note: the notification-permission hook lives in DeviceDetailView's
    // .onChange, which wraps this whole section — no callback needed here.

    private var alerts: BatteryNotificationSettings {
        settings.profile.batteryNotifications
    }

    var body: some View {
        Section {
            Toggle(l10n(.settingsBatteryShowPercent), isOn: $settings.profile.showBatteryPercent)
                .help(l10n(.settingsBatteryShowPercentHelp))
        } header: {
            Text(l10n(.settingsBatteryMenuBarSection))
        }

        Section {
            if alerts.thresholds.isEmpty {
                Text(l10n(.settingsBatteryNoThresholds))
                    .foregroundStyle(.secondary)
            } else {
                ForEach(alerts.thresholds) { threshold in
                    thresholdRow(threshold)
                }
            }
            Button(l10n(.settingsBatteryAddThreshold), systemImage: "plus") {
                settings.profile.batteryNotifications
                    .addThreshold(percent: alerts.suggestedNewThreshold)
            }
            .disabled(alerts.thresholds.count >= BatteryNotificationSettings.percentRange.count)
        } header: {
            Text(l10n(.settingsBatteryThresholdsSection))
        } footer: {
            Text(l10n(.settingsBatteryNotificationsHelp))
                .font(.footnote)
                .foregroundStyle(.secondary)
        }

        Section {
            Toggle(l10n(.settingsBatteryFull), isOn: Binding(
                get: { alerts.fullEnabled },
                set: { settings.profile.batteryNotifications.fullEnabled = $0 }
            ))
        } header: {
            Text(l10n(.settingsBatteryNotificationsSection))
        }
    }

    // thresholdRow(_:) — copy the ENTIRE private func from
    // BatterySettingsTab.swift unchanged, except every
    // `settings.settings.batteryNotifications` is already
    // `settings.profile.batteryNotifications` there — keep as-is.
}
```

(The implementer copies `thresholdRow` verbatim from `Sources/ZteMenu/Settings/BatterySettingsTab.swift` — it already binds through `settings.profile`. The `.onChange(of: alerts)` notification-permission hook moves to `DeviceDetailView` below so it wraps the whole battery group.)

`Sources/ZteMenu/Settings/DeviceSignInSection.swift`:

```swift
import SwiftUI

/// The device's panel credentials. The password lives in the profile's own
/// Keychain slot; the username is stored on the profile and shown only for
/// providers whose login has one.
///
/// The field saves itself — on submit and when it loses focus — so it
/// behaves like every other control. Only deletion stays an explicit
/// button, because it destroys a stored credential.
struct DeviceSignInSection: View {
    @Bindable var settings: SettingsStore
    let l10n: L10n

    private let profileID: UUID
    @State private var password: String
    @FocusState private var focused: Bool

    init(settings: SettingsStore, l10n: L10n) {
        self.settings = settings
        self.l10n = l10n
        let id = settings.profile.id
        self.profileID = id
        _password = State(initialValue: Keychain.password(for: id) ?? "")
    }

    private var capabilities: ModemCapabilities {
        ProviderCatalog.descriptor(for: settings.profile.provider).capabilities
    }

    var body: some View {
        Section {
            if capabilities.needsUsername {
                TextField(l10n(.settingsUsernameField), text: $settings.profile.username)
            }
            SecureField(l10n(.settingsPasswordField), text: $password)
                .focused($focused)
                .onSubmit(save)
                .onChange(of: focused) { wasFocused, isFocused in
                    if wasFocused && !isFocused { save() }
                }

            Button(l10n(.settingsDeletePassword), role: .destructive) {
                Keychain.deletePassword(for: profileID)
                password = ""
            }
            .disabled(password.isEmpty)
        } header: {
            Text(l10n(.settingsSignInSection))
        } footer: {
            Text(l10n(capabilities.passwordRole == .requiredForAll
                        ? .settingsPasswordHelpRequired
                        : .settingsPasswordHelp))
                .foregroundStyle(.secondary)
        }
        .onDisappear(perform: save)
    }

    private func save() {
        guard !password.isEmpty else { return }
        Keychain.setPassword(password, for: profileID)
    }
}
```

`Sources/ZteMenu/Settings/DeviceDetailView.swift`:

```swift
import SwiftUI

/// Everything about ONE device: identity, detection, credentials, and the
/// per-device presentation preferences that used to be their own tabs.
struct DeviceDetailView: View {
    @Bindable var settings: SettingsStore
    let l10n: L10n
    let onNotificationsEnabled: () -> Void

    /// Read once at appear: reading CoreWLAN in `body` would hit the Wi-Fi
    /// daemon on every redraw.
    @State private var currentSSID: String?

    private var capabilities: ModemCapabilities {
        ProviderCatalog.descriptor(for: settings.profile.provider).capabilities
    }

    var body: some View {
        Form {
            Section {
                TextField(l10n(.settingsDeviceName),
                          text: $settings.profile.name,
                          prompt: Text(settings.profile.displayTitle))
                Picker(l10n(.settingsDeviceType), selection: Binding(
                    get: { settings.profile.provider },
                    set: { settings.profile = settings.profile.adopting(provider: $0) }
                )) {
                    ForEach(ProviderKind.allCases, id: \.self) { kind in
                        Text(ProviderCatalog.descriptor(for: kind).displayName).tag(kind)
                    }
                }
            }

            Section {
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

            DeviceSignInSection(settings: settings, l10n: l10n)

            Section {
                Toggle(l10n(.settingsStatsBasic), isOn: $settings.profile.stats.basic)
                Toggle(l10n(.settingsStatsRadio), isOn: $settings.profile.stats.radio)
                Toggle(l10n(.settingsStatsTransfer), isOn: $settings.profile.stats.transfer)
                Toggle(l10n(.settingsStatsUptime), isOn: $settings.profile.stats.uptime)
            } header: {
                Text(l10n(.settingsStatsSection))
            }

            if capabilities.hasBattery {
                DeviceBatterySection(settings: settings, l10n: l10n)
            }
        }
        .formStyle(.grouped)
        .task { currentSSID = CoreWLANReader().currentSSID() }
        .onChange(of: settings.profile.batteryNotifications) { old, new in
            guard new.isAnyEnabled, !old.isAnyEnabled else { return }
            onNotificationsEnabled()
        }
    }
}
```

`Sources/ZteMenu/Settings/DevicesSettingsTab.swift`:

```swift
import SwiftUI

/// The device manager: every configured profile in matcher-priority order,
/// with the selected one edited below. Stored order IS priority — the first
/// matching profile wins, so the rows support drag reordering.
struct DevicesSettingsTab: View {
    @Bindable var settings: SettingsStore
    /// Read-only: marks the profile the last refresh actually matched.
    let store: ModemStore
    let l10n: L10n
    let onNotificationsEnabled: () -> Void

    @State private var confirmingRemoval = false

    var body: some View {
        VStack(spacing: 0) {
            List(selection: Binding(
                get: { settings.editedProfileID ?? settings.settings.profiles.first?.id },
                set: { settings.editedProfileID = $0 }
            )) {
                ForEach(settings.settings.profiles) { profile in
                    row(for: profile).tag(profile.id)
                }
                .onMove { offsets, destination in
                    settings.settings.moveProfiles(fromOffsets: offsets, toOffset: destination)
                }
            }
            .frame(height: 148)

            HStack(spacing: 12) {
                Menu {
                    ForEach(ProviderKind.allCases, id: \.self) { kind in
                        Button(ProviderCatalog.descriptor(for: kind).displayName) {
                            settings.editedProfileID = settings.settings.addProfile(provider: kind)
                        }
                    }
                } label: {
                    Label(l10n(.settingsDeviceAdd), systemImage: "plus")
                }
                .fixedSize()

                Button(role: .destructive) {
                    confirmingRemoval = true
                } label: {
                    Label(l10n(.settingsDeviceRemove), systemImage: "minus")
                }
                .disabled(settings.settings.profiles.count <= 1)
                .confirmationDialog(l10n(.settingsDeviceRemoveConfirm),
                                    isPresented: $confirmingRemoval) {
                    Button(l10n(.settingsDeviceRemove), role: .destructive, action: removeSelected)
                }
                Spacer()
            }
            .buttonStyle(.borderless)
            .labelStyle(.titleAndIcon)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider()

            // `.id` re-creates the detail (and its @State password) when the
            // selection moves to another device — without it, the sign-in
            // field would keep showing the previous device's credential.
            DeviceDetailView(settings: settings, l10n: l10n,
                             onNotificationsEnabled: onNotificationsEnabled)
                .id(settings.profile.id)
        }
    }

    private func row(for profile: ModemProfile) -> some View {
        HStack(spacing: 8) {
            Circle()
                .fill(store.activeProfile?.id == profile.id ? Color.green : Color.clear)
                .frame(width: 8, height: 8)
                .help(l10n(.settingsDeviceActiveNow))
            VStack(alignment: .leading, spacing: 2) {
                Text(profile.displayTitle)
                Text(profile.matchMode == .ssid
                        ? "SSID: \(profile.ssid)"
                        : "IP: \(profile.modemIP)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(ProviderCatalog.descriptor(for: profile.provider).displayName)
                .font(.caption)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(.quaternary, in: Capsule())
        }
        .padding(.vertical, 2)
    }

    private func removeSelected() {
        let id = settings.profile.id
        guard settings.settings.removeProfile(id: id) else { return }
        // The credential dies with the device.
        Keychain.deletePassword(for: id)
        settings.editedProfileID = settings.settings.profiles.first?.id
    }
}
```

- [ ] **Step 6: Run the full suite** (the new views compile but are not yet reachable; the L10n completeness tests verify the nine new keys in both languages)

Run: `swift test 2>&1 | tail -3`
Expected: PASS, 0 failures — delta: +2 (the SettingsStore selection tests).

- [ ] **Step 7: Commit**

```bash
git add -A && git commit -m "feat(settings): device manager views and edited-profile selection"
```

---

### Task 8: Rewire the settings window; delete the retired tabs

**Files:**
- Modify: `Sources/ZteMenu/Settings/SettingsTab.swift`
- Modify: `Sources/ZteMenu/SettingsView.swift`
- Modify: `Sources/ZteMenu/ZteMenuApp.swift`
- Modify: `Sources/ZteMenu/Settings/GeneralSettingsTab.swift`
- Delete: `Sources/ZteMenu/Settings/PanelSettingsTab.swift`, `Sources/ZteMenu/Settings/BatterySettingsTab.swift`, `Sources/ZteMenu/Settings/AccountSettingsTab.swift`
- Modify: `Sources/ZteMenu/Localization/LocKey.swift`, both `Localizable.strings`
- Modify: `Tests/ZteMenuTests/SettingsTabTests.swift`

**Interfaces:**
- Produces: `SettingsTab` = `general / devices / updates` (symbols `gearshape` / `wifi.router` / `arrow.triangle.2.circlepath`; titles `settingsTabGeneral` / `settingsTabDevices` / `settingsTabUpdates`); `visible(for:)` deleted; `SettingsView.init` gains `store: ModemStore`; window width 560.
- Consumes: Task 7 views.

- [ ] **Step 1: Rewrite the tab tests.** Replace the body of `Tests/ZteMenuTests/SettingsTabTests.swift`'s order/symbol/visibility tests:

```swift
    func testTabOrderIsStable() {
        XCTAssertEqual(SettingsTab.allCases.map(\.rawValue),
                       ["general", "devices", "updates"])
    }
```

(keep `testEveryTabHasADistinctSymbol`, `testEveryTabHasADistinctTitleKey`, and `testEveryTabTitleHasAnEntryInBothLanguages` unchanged — they iterate `allCases`; DELETE `testEveryTabIsVisibleForABatteryCapableProvider`.)

- [ ] **Step 2: Run to verify failure**

Run: `swift test --filter SettingsTabTests 2>&1 | tail -5`
Expected: FAIL — order assertion sees five tabs.

- [ ] **Step 3: Implement.** `Sources/ZteMenu/Settings/SettingsTab.swift` becomes:

```swift
import Foundation

/// The settings window's tabs, in display order.
///
/// A plain model rather than an inline list so the toolbar and the content
/// switch cannot drift apart, and so the pairing of tab to icon and label is
/// unit testable. Per-device settings live inside the Devices tab's detail
/// view, so no tab is capability-gated anymore.
enum SettingsTab: String, CaseIterable, Identifiable, Sendable {
    case general
    case devices
    case updates

    var id: String { rawValue }

    /// SF Symbol shown above the tab's title.
    var symbolName: String {
        switch self {
        case .general: return "gearshape"
        case .devices: return "wifi.router"
        case .updates: return "arrow.triangle.2.circlepath"
        }
    }

    var titleKey: LocKey {
        switch self {
        case .general: return .settingsTabGeneral
        case .devices: return .settingsTabDevices
        case .updates: return .settingsTabUpdates
        }
    }
}
```

`Sources/ZteMenu/SettingsView.swift`: add `store` (stored `private let store: ModemStore` + init param after `updater`), change the frame to `.frame(width: 560)`, `ForEach(SettingsTab.allCases)`, and the content switch to:

```swift
        switch tab {
        case .general:
            GeneralSettingsTab(settings: settings, l10n: l10n, loginItem: loginItem)
        case .devices:
            DevicesSettingsTab(settings: settings, store: store, l10n: l10n,
                               onNotificationsEnabled: onNotificationsEnabled)
        case .updates:
            UpdatesSettingsTab(updater: updater, l10n: l10n)
        }
```

`Sources/ZteMenu/ZteMenuApp.swift`: pass it —

```swift
            SettingsView(settings: settings,
                         updater: appDelegate.updater,
                         store: appDelegate.store,
                         l10n: l10n,
                         loginItem: appDelegate.loginItem,
                         onNotificationsEnabled: appDelegate.requestNotificationAuthorization)
```

`Sources/ZteMenu/Settings/GeneralSettingsTab.swift`: delete the network `Section` (the device-type/detection/SSID block) AND the `currentSSID` state + its `.task` line (keep `loginItem.refresh()` in the task); insert in its place, between the login-item section and the language section:

```swift
            Section {
                Toggle(l10n(.settingsShowWhenDisconnected),
                       isOn: $settings.settings.showWhenDisconnected)
                    .help(l10n(.settingsShowWhenDisconnectedHelp))
            }
```

Delete the three retired tab files:

```bash
git rm Sources/ZteMenu/Settings/PanelSettingsTab.swift \
       Sources/ZteMenu/Settings/BatterySettingsTab.swift \
       Sources/ZteMenu/Settings/AccountSettingsTab.swift
```

Then delete the transitional single-slot block from `Sources/ZteMenu/Keychain.swift` (the `// MARK: Transitional single-slot API` comment and the three zero-arg functions below it) — `AccountSettingsTab` was its last caller.

Localization cleanup — delete from `LocKey.swift` the cases `settingsTabPanel`, `settingsTabAccount`, `settingsTabBattery`, `settingsAccountSection`, and remove the same four keys (`settings.tab.panel`, `settings.tab.account`, `settings.tab.battery`, `settings.account.section`) from BOTH `.strings` files. (The completeness tests fail on any orphan in either direction — that is the net.)

- [ ] **Step 4: Run the full suite**

Run: `swift test 2>&1 | tail -3`
Expected: PASS, 0 failures — delta: −1 (the deleted visibility test). If `Tests/ZteMenuTests/SettingsWindowTests.swift` pins the window width or the removed tabs, update those assertions to the new reality (width 560, three tabs) — report exactly what you changed.

- [ ] **Step 5: Commit**

```bash
git add -A && git commit -m "feat(settings): three-tab window with the device manager at its centre"
```

---

### Task 9: Retirement gates and end-to-end verification

**Files:**
- Modify: whatever the gates flag (expected: nothing)

- [ ] **Step 1: Gates.**

Run: `grep -rn "PanelSettingsTab\|BatterySettingsTab\|AccountSettingsTab\|visible(for:\|settingsTabPanel\|settingsTabAccount\|settingsTabBattery\|settingsAccountSection" Sources Tests --include="*.swift"`
Expected: no output.

Run: `grep -rn "Keychain.password()\|setPassword(\"\|deletePassword()" Sources Tests --include="*.swift" | grep -v "for:"`
Expected: no output (every Keychain call is per-profile).

Any hit is an unfinished migration — fix it before continuing.

- [ ] **Step 2: Full suite + bundle**

Run: `swift test 2>&1 | tail -3`
Expected: PASS, 0 failures (net plan delta: +21 vs the 151 baseline, parallel-session drift aside).

Run: `./scripts/build-app.sh 2>&1 | tail -4`
Expected: bundle assembles; the script's own launch smoke test passes.

- [ ] **Step 3: Live verification (manual, needs the human — document, don't skip).** With the freshly built app running on the Asus network: Settings → Devices shows the ZTE profile (migrated password intact — verify the transfer counters still appear when next on the ZTE network) and after "Add device → Asus", the new profile with IP 192.168.50.1; enter the router's username+password in Sign-in; within a refresh the Asus row gains the green dot, the menu bar shows the `wifi.router` symbol, and the popover header shows the device (name or "Asus · 192.168.50.1") with uptime and total-transfer rows and no battery UI. Reordering rows and removing a test-added device must behave. This step's outcome goes in the final report to the user.

- [ ] **Step 4: Commit** (only if the gates forced fixes; otherwise nothing to commit)

```bash
git add -A && git commit -m "chore(settings): retire the last single-device remnants"
```

---

## Post-Plan Notes

- **Release notes:** the settings window is reorganized (General / Devices / Updates); battery, stats and credentials now live per device inside Devices. Asus (Asuswrt) routers are supported.
- **Deliberately deferred:** per-profile history (charts mix devices' samples if two battery devices ever coexist), Asus extras (clients/CPU/RAM/monthly), tolerant unknown-`provider` decode (needed before any FUTURE provider ships in an update, so a downgrade doesn't reset settings — tracked from the previous plan's final review).
- The `pause` injection in `AsusClient` is the only concession to testability; production behaviour is a plain 1-second sleep off the main actor.
