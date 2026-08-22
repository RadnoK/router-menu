# ZTE Menu

A native macOS menu bar app that shows the status of a **ZTE U50 5G** modem:
battery level, signal strength, network type, carrier, and transfer statistics.
The icon appears **only** while you're connected to the modem.

Built with Swift + SwiftUI (SwiftPM, no Xcode project), an `LSUIElement` app —
it lives in the menu bar, with no Dock icon.

## Features

- **Menu bar icon** (`cellularbars`) — changes with signal strength; visible only
  on the modem's network, and disappears off it.
- **Click-through panel** — a readable popover with sections:
  - Battery (dynamic icon by level, charging indicator)
  - Signal (description + bars) and network type (5G / LTE / …)
  - Radio details: RSRP, SINR
  - Transfer: current speed ↓↑, total and monthly (in GB)
  - Carrier, connection time
  - Mini charts of battery and transfer (last 24h, Swift Charts)
- **Settings window**:
  - Network detection mode: **by WiFi name** or **by modem IP reachability**
    (IP mode doesn't require location permission)
  - Network name (SSID) and the modem's IP address
  - Toggle stat groups shown in the panel
  - Modem password (for transfer counters) — stored in **Keychain**
- **24h history** of battery and transfer — saved locally, survives a restart.
- **Localization** — English and Polish. The app follows your system language by
  default; you can force either language in Settings under **Appearance**.

## Requirements

- macOS 14+ (verified on macOS 26)
- Swift 6.3 toolchain
- ZTE U50 modem (panel at `192.168.0.1`)

## Installation

```bash
brew tap RadnoK/tap
brew install --cask zte-menu
```

The app is Developer ID signed and notarized by Apple, so it launches without
Gatekeeper warnings. The binary is universal (Apple Silicon + Intel).

Alternatively: download the `.zip` from [Releases](https://github.com/RadnoK/zte-menu/releases)
and move `ZTE Menu.app` to `/Applications`.

## Updates

The app checks for new versions on its own (Sparkle). In the settings window,
under **Updates**, you can:

- turn automatic checking on or off,
- pick a frequency (daily / weekly),
- turn on automatic downloading and installing,
- check for updates manually with the **Check Now** button.

Updates are signed with an EdDSA key and verified before installation.

## Building and running

```bash
# tests
swift test

# build and package into a .app
./scripts/build-app.sh

# run
open "dist/ZTE Menu.app"
```

On first launch (in "by WiFi name" mode) macOS will ask for **location**
permission — it's required because on newer macOS versions the WiFi network
name is only readable with that permission granted. Alternatively, switch to
**"by IP reachability"** mode in settings, which doesn't require it.

## Transfer statistics (login)

Battery, signal, network, and **current speed** are available without logging in.
The **total** and **monthly** counters (GB) are only exposed by the modem after
logging in — enter the modem panel password in the settings window (stored in
Keychain).

## Architecture

Layered, with pure logic that's unit tested (64 tests) and thin, injected
system-facing layers:

| Layer | Files |
|---------|-------|
| Model / parsing | `ModemData`, `ByteFormat` |
| Modem communication | `ModemClient`, `ZTEAuth` (login), `SessionHTTP` |
| Network detection | `NetworkDetector`, `WiFiMonitor`, `LocationPermission` |
| State and persistence | `ModemStore`, `SettingsStore`, `HistoryStore`, `Keychain` |
| Localization | `AppLanguage`, `LocKey`, `L10n` |
| UI | `PopoverView`, `SettingsView`, `BatteryChartView`, `TransferChartView` |
| Lifecycle / scene | `AppDelegate`, `ZteMenuApp`, `MenuBarPresentation` |

Modem login (verified live) uses a double SHA256 hash of the password with the
`LD` token and keeps the session alive via the `stok` cookie. All communication
is local (LAN) — the app never sends any data externally. The password never
ends up in the repository or on disk outside Keychain.

## Note: menu bar managers (e.g. Bartender)

Menu bar managers can automatically hide newly appearing icons. If you don't
see the "ZTE Menu" icon, check your manager's hidden area and set it to always
visible.

## Privacy

- Communicates only with the local modem (`192.168.0.1`), no external services.
- Modem password stored in the macOS Keychain.
- History (battery/transfer) saved locally in `~/Library/Application Support/zte-menu/`.
- Location permission used only to read the WiFi network name (a macOS
  requirement); the app never tracks or sends location data.

## Releasing a new version

Releasing is fully automated — just bump the version and push a tag:

```bash
# 1. bump the version in Info.plist (must match the tag)
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString 0.2.0" Resources/Info.plist
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion 0.2.0" Resources/Info.plist

# 2. commit and tag
git commit -am "chore: version 0.2.0"
git tag v0.2.0 && git push origin main v0.2.0
```

GitHub Actions builds the universal binary, signs it with Developer ID,
notarizes it, publishes the Release, generates a signed appcast on the
`gh-pages` branch, and bumps the cask in [RadnoK/homebrew-tap](https://github.com/RadnoK/homebrew-tap).

Local release (skipping CI): `./scripts/release.sh <version>`.
