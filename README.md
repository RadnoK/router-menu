# ZTE Menu

Natywna aplikacja macOS w pasku menu, która pokazuje status modemu **ZTE U50 5G**:
poziom baterii, moc sygnału, typ sieci, operatora oraz statystyki transferu.
Ikona pojawia się **tylko** gdy jesteś podłączony do modemu.

Zbudowana w Swift + SwiftUI (SwiftPM, bez projektu Xcode), aplikacja typu
`LSUIElement` — żyje na pasku menu, bez ikony w Docku.

## Funkcje

- **Ikona na pasku** (`cellularbars`) — zmienia się wg siły sygnału; widoczna tylko
  w sieci modemu, poza nią znika.
- **Panel po kliknięciu** — czytelny popover z sekcjami:
  - Bateria (dynamiczna ikona wg poziomu, wskaźnik ładowania)
  - Sygnał (opis + słupki) i typ sieci (5G / LTE / …)
  - Szczegóły radiowe: RSRP, SINR
  - Transfer: bieżąca prędkość ↓↑, łączny i miesięczny (w GB)
  - Operator, czas połączenia
  - Mini-wykresy baterii i transferu (ostatnie 24h, Swift Charts)
- **Okno ustawień**:
  - Tryb wykrywania sieci: **po nazwie WiFi** albo **po osiągalności IP** modemu
    (tryb IP nie wymaga uprawnień lokalizacji)
  - Nazwa sieci (SSID) i adres IP modemu
  - Włączanie/wyłączanie grup statystyk w panelu
  - Hasło do modemu (do liczników transferu) — przechowywane w **Keychain**
- **Historia 24h** baterii i transferu — zapisywana lokalnie, przeżywa restart.

## Wymagania

- macOS 14+ (weryfikowane na macOS 26)
- Swift 6.3 toolchain
- Modem ZTE U50 (panel pod `192.168.0.1`)

## Instalacja

```bash
brew tap RadnoK/tap
brew install --cask zte-menu
```

Aplikacja jest podpisana Developer ID i notaryzowana przez Apple, więc uruchamia
się bez ostrzeżeń Gatekeepera. Binarka jest uniwersalna (Apple Silicon + Intel).

Alternatywnie: pobierz `.zip` z [Releases](https://github.com/RadnoK/zte-menu/releases)
i przenieś `ZTE Menu.app` do `/Applications`.

## Aktualizacje

Aplikacja sama sprawdza dostępność nowych wersji (Sparkle). W oknie ustawień,
w sekcji **Aktualizacje**, możesz:

- włączyć lub wyłączyć automatyczne sprawdzanie,
- wybrać częstotliwość (codziennie / co tydzień),
- włączyć automatyczne pobieranie i instalowanie,
- sprawdzić dostępność aktualizacji ręcznie przyciskiem **Sprawdź teraz**.

Aktualizacje są podpisane kluczem EdDSA i weryfikowane przed instalacją.

## Budowanie i uruchamianie

```bash
# testy
swift test

# zbuduj i spakuj do .app
./scripts/build-app.sh

# uruchom
open "dist/ZTE Menu.app"
```

Przy pierwszym uruchomieniu (w trybie „po nazwie WiFi") macOS poprosi o zgodę na
**lokalizację** — jest niezbędna, bo na nowszych macOS nazwa sieci WiFi jest
czytelna tylko z tą zgodą. Alternatywnie w ustawieniach przełącz na tryb
**„po osiągalności IP"**, który zgody nie wymaga.

## Statystyki transferu (logowanie)

Bateria, sygnał, sieć i **bieżąca prędkość** transferu są dostępne bez logowania.
Liczniki **łączne** i **miesięczne** (GB) modem udostępnia dopiero po zalogowaniu —
wpisz hasło do panelu modemu w oknie ustawień (zapisywane w Keychain).

## Architektura

Warstwowa, z czystą logiką testowaną jednostkowo (44 testy) i cienkimi,
wstrzykiwanymi warstwami systemowymi:

| Warstwa | Pliki |
|---------|-------|
| Model / parsowanie | `ModemData`, `ByteFormat` |
| Komunikacja z modemem | `ModemClient`, `ZTEAuth` (logowanie), `SessionHTTP` |
| Wykrywanie sieci | `NetworkDetector`, `WiFiMonitor`, `LocationPermission` |
| Stan i persystencja | `ModemStore`, `SettingsStore`, `HistoryStore`, `Keychain` |
| UI | `PopoverView`, `SettingsView`, `BatteryChartView`, `TransferChartView` |
| Cykl życia / scena | `AppDelegate`, `ZteMenuApp`, `MenuBarPresentation` |

Logowanie do modemu (zweryfikowane na żywo) używa dwukrotnego SHA256 hasła z
tokenem `LD` i utrzymuje sesję przez cookie `stok`. Cała komunikacja jest lokalna
(LAN) — aplikacja nie wysyła żadnych danych na zewnątrz. Hasło nigdy nie trafia
do repozytorium ani na dysk poza Keychain.

## Uwaga: menedżery paska menu (np. Bartender)

Menedżery paska menu mogą automatycznie chować nowo pojawiające się ikony. Jeśli
nie widzisz ikony „ZTE Menu", sprawdź ukryty obszar swojego menedżera i ustaw ją
jako zawsze widoczną.

## Prywatność

- Komunikacja wyłącznie z lokalnym modemem (`192.168.0.1`), bez zewnętrznych usług.
- Hasło modemu przechowywane w macOS Keychain.
- Historia (bateria/transfer) zapisywana lokalnie w `~/Library/Application Support/zte-menu/`.
- Uprawnienie lokalizacji używane wyłącznie do odczytu nazwy sieci WiFi (wymóg macOS);
  aplikacja nie śledzi ani nie wysyła lokalizacji.

## Wydawanie nowej wersji

Wydanie jest w pełni zautomatyzowane — wystarczy podbić wersję i wypchnąć tag:

```bash
# 1. podbij wersję w Info.plist (musi zgadzać się z tagiem)
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString 0.2.0" Resources/Info.plist
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion 0.2.0" Resources/Info.plist

# 2. commit i tag
git commit -am "chore: wersja 0.2.0"
git tag v0.2.0 && git push origin main v0.2.0
```

GitHub Actions zbuduje binarkę uniwersalną, podpisze ją Developer ID,
znotaryzuje, opublikuje Release, wygeneruje podpisany appcast na gałęzi
`gh-pages` i podbije cask w [RadnoK/homebrew-tap](https://github.com/RadnoK/homebrew-tap).

Wydanie lokalne (z pominięciem CI): `./scripts/release.sh <wersja>`.
