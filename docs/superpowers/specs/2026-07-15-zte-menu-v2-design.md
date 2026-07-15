# zte-menu v2 — panel, ustawienia, wykresy i transfer

**Data:** 2026-07-15
**Status:** Zatwierdzony projekt
**Bazuje na:** v1 (`2026-07-15-zte-menu-design.md`), odkrycia API
(`2026-07-15-modem-api-findings.md`, `2026-07-15-modem-login-findings.md`)

## Cel

Rozbudowa aplikacji menu bar o: (1) ładniejszy, czytelny panel zamiast
natywnego menu, (2) okno ustawień (wybór sieci, wybór widocznych statystyk),
(3) wykres baterii i transferu w czasie (24h), (4) statystyki transferu
(prędkość, łączny, miesięczny) z logowaniem do modemu.

## Wymagania funkcjonalne

### Panel (popover)
- Kliknięcie ikony otwiera **popover** (SwiftUI), nie natywne menu — pełna
  kontrola typografii/kolorów, brak nieczytelnych „disabled" pozycji.
- Sekcje statystyk renderowane wg ustawień widoczności.
- Mini-wykres baterii (24h) i mini-wykres transferu (24h).
- Stopka: „Odśwież", „Ustawienia", „Zakończ".

### Ustawienia (osobne okno)
- **Tryb wykrywania sieci** (przełącznik):
  - `bySSID` — dopasowanie po nazwie WiFi (wymaga uprawnień lokalizacji).
  - `byIPReachable` — modem odpowiada pod IP (NIE wymaga lokalizacji).
- **Nazwa sieci** (SSID, domyślnie `ZTE_B4B622`) — edytowalna; pokazana
  aktualnie wykryta sieć dla ułatwienia.
- **IP modemu** (domyślnie `192.168.0.1`) — edytowalne.
- **Widoczność statystyk** (checkboxy, grupy):
  - Bateria + sygnał + sieć + operator
  - Szczegóły radiowe (RSRP/RSRQ/SINR)
  - Transfer (prędkość + łączny + miesięczny)
  - Czas połączenia / uptime
- **Interwał odświeżania** (domyślnie 60 s).
- **Konto modemu**: pole hasła (zapis do Keychain). Opcjonalne — bez hasła
  aplikacja działa, z hasłem dochodzą liczniki total/monthly.

### Statystyki transferu
- Bieżąca prędkość ↓↑ (bez logowania — `realtime_*_thrpt`).
- Łączny transfer sesji (`realtime_*_bytes`) — z logowaniem.
- Miesięczne zużycie (`monthly_*_bytes`) — z logowaniem.
- Wykres transferu over time (24h) — z próbek historii.

### Wykresy (Swift Charts)
- **Bateria**: % w czasie (24h), linia z wypełnieniem.
- **Transfer**: prędkość ↓↑ w czasie (24h).

## Architektura

Nowe/rozbudowane jednostki (każda jedno zadanie):

- **`SettingsStore`** (`@Observable`, `UserDefaults`) — tryb sieci, SSID, IP,
  widoczność statystyk, interwał.
- **`Keychain`** — zapis/odczyt hasła modemu (Keychain Services).
- **`HistoryStore`** (`@Observable`, JSON w Application Support) — próbki 24h
  `{timestamp, batteryPercent, totalRxBytes, totalTxBytes}`; wyliczanie
  prędkości z różnic; przycinanie do 24h; zapis/odczyt z dysku.
- **`ModemClient`** (rozbudowa) — dwa tryby: status (bez logowania) i traffic
  (z logowaniem). Logowanie ZTE, sesja przez cookie `stok`, auto-relogin raz.
- **`ModemData`** (rozbudowa) — opcjonalne pola transferu i uptime.
- **`NetworkDetector`** (rozbudowa `WiFiMonitor`) — tryb `bySSID` lub
  `byIPReachable` wg ustawień.
- **`PopoverView`** — panel SwiftUI (sekcje + wykresy + stopka).
- **`SettingsView`** — okno ustawień (zakładki/sekcje).
- **`BatteryChartView`**, **`TransferChartView`** — wykresy Swift Charts.
- **`ModemStore`** (rozbudowa) — spina ustawienia, klienta, historię;
  po każdym refreshu dopisuje próbkę do `HistoryStore`.

## Logowanie do modemu (zweryfikowane na żywo)

```
LD = GET goform_get_cmd_process?cmd=LD
password = SHA256( SHA256(hasło).hex.upper() + LD ).hex.upper()
POST goform_set_cmd_process  body: isTest=false&goformId=LOGIN&password=<hash>
sukces: {"result":"0"}; sesja: cookie stok
```

- Klient: `URLSession` z własnym `HTTPCookieStorage` (izolacja sesji).
- Przy `result != "0"` → błąd logowania („sprawdź hasło").
- Puste liczniki mimo hasła (wygasła sesja) → jednorazowy relogin, potem błąd.

## Pola transferu (po zalogowaniu)

`realtime_rx_bytes`/`realtime_tx_bytes` (sesja), `realtime_rx_thrpt`/
`realtime_tx_thrpt` (prędkość B/s, bez logowania), `total_rx_bytes`/
`total_tx_bytes`, `monthly_rx_bytes`/`monthly_tx_bytes`, `realtime_time`
(uptime sesji, s), `monthly_time` (uptime miesięczny, s). Wartości to bajty
jako stringi; GB = bajty/1024³. `total_connected_time` puste — nie używać.

## Persystencja

- **Ustawienia** → `UserDefaults` (klucze prefiksowane).
- **Hasło** → Keychain (usługa `io.8lines.zte-menu`).
- **Historia 24h** → JSON w
  `~/Library/Application Support/zte-menu/history.json`. Próbki co interwał,
  przycinane do 24h, zapisywane po każdej próbce (throttled).

## Wygląd (rozwiązuje nieczytelne „disabled options")

- Popover = zwykły widok SwiftUI: wartości pełnokolorowe, wyraźna hierarchia
  (tytuł sekcji / etykieta / wartość), SF Symbols przy pozycjach.
- Kolory sygnalizujące (bateria wg poziomu, sygnał wg siły).
- Natywny materiał tła / Liquid Glass (macOS 26).
- Na etapie implementacji: skille `frontend-design`, `swiftui-liquid-glass`,
  `swiftui-ui-patterns`.

## Ikona na pasku (bez zmian koncepcyjnych)

`cellularbars`, widoczna tylko gdy wykryto sieć ZTE (wg trybu z ustawień).
W trybie `byIPReachable` nie wymaga uprawnień lokalizacji.

## Testowanie

- `SettingsStore`, `HistoryStore` (przycinanie 24h, wyliczanie prędkości z
  różnic), logowanie (hash — wektor testowy), parser transferu, tryby
  `NetworkDetector` — testy jednostkowe.
- Keychain, wykresy, popover, okno ustawień — weryfikacja ręczna (na żywo).

## Poza zakresem (YAGNI)

- Historia > 24h / baza SwiftData (na razie JSON 24h wystarcza).
- Powiadomienia (np. niski poziom baterii).
- Sterowanie modemem (restart, SMS) — tylko odczyt.
- Auto-start przy logowaniu (osobna, późniejsza funkcja).

## Migracja z v1

- `Config.swift` (stałe) → wartości domyślne w `SettingsStore`; `Config`
  zostaje jako źródło defaultów.
- Menu (`.menu`) → popover (`.window`); `MenuBarView` → `PopoverView`.
- `WiFiMonitor` → `NetworkDetector` z trybami.
