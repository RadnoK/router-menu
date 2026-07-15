# zte-menu — aplikacja menu bar dla modemu ZTE U50 (5G)

**Data:** 2026-07-15
**Status:** Zatwierdzony projekt

## Cel

Natywna aplikacja macOS w pasku menu (menu bar), która pokazuje status
modemu **ZTE U50 5G**: poziom baterii i moc sygnału/zasięgu. Ikona pojawia
się na pasku **wyłącznie** gdy Mac jest podłączony do sieci WiFi modemu
(`ZTE_B4B622`); poza tą siecią ikona znika całkowicie.

## Wymagania funkcjonalne

- Ikona SF Symbol `cellularbars` na pasku menu, zmieniająca wygląd wg siły sygnału.
- Ikona widoczna **tylko** gdy aktualne SSID = `ZTE_B4B622`; w innym wypadku znika.
- Po kliknięciu — rozwijane menu ze szczegółami:
  - Poziom baterii (%)
  - Moc sygnału (opis + szczegóły RSRP/RSRQ/SINR, jeśli modem je udostępnia)
  - Typ sieci (5G / LTE / itd.)
  - Operator
  - Akcje: „Odśwież teraz", „Zakończ"
- Odświeżanie danych **co 60 sekund** (oraz przy starcie i przy zmianie sieci WiFi).

## Wymagania niefunkcjonalne

- Aplikacja typu **LSUIElement** — brak ikony w Docku, tylko pasek menu.
- Natywny **Swift + SwiftUI**, budowany przez **SwiftPM** (bez projektu Xcode),
  pakowany skryptem do `.app` (skill `macos-spm-app-packaging`).
- Uruchamialna jednym poleceniem, bez otwierania Xcode.

## Architektura

Podział na warstwy, każda z jednym zadaniem:

- **`ModemClient`** — komunikacja z modemem ZTE: logowanie do panelu i pobieranie
  surowych danych (bateria, sygnał, typ sieci, operator) przez wewnętrzne API
  (`goform_get_cmd_process` lub równoważne — do zweryfikowania na żywo).
- **`WiFiMonitor`** — sprawdza aktualne SSID przez CoreWLAN; decyduje o widoczności ikony.
- **`ModemStore`** — stan aplikacji (`@Observable`): aktualne dane, status
  połączenia, timer odświeżania co 60 s. Spina `WiFiMonitor` + `ModemClient`.
- **`MenuBarView`** — SwiftUI: ikona na pasku + rozwijane menu ze szczegółami.
- **`App` / `AppDelegate`** — punkt wejścia, `MenuBarExtra`, konfiguracja LSUIElement.
- **`Config.swift`** — konfiguracja: adres IP modemu, hasło do panelu, nazwa SSID.

## Przepływ danych i logika widoczności

1. Timer co 60 s (oraz przy starcie i przy zmianie sieci) uruchamia cykl odświeżania.
2. `WiFiMonitor` sprawdza SSID:
   - **≠ `ZTE_B4B622`** → stan `hidden`, ikona znika całkowicie z paska.
   - **= `ZTE_B4B622`** → dalej.
3. `ModemClient` loguje się (jeśli trzeba) i pobiera dane:
   - Sukces → stan `connected(dane)`, ikona widoczna z aktualnym sygnałem.
   - Błąd → stan `error`, ikona widoczna, menu pokazuje komunikat błędu.

### Stany aplikacji

- `hidden` — nie w sieci ZTE_B4B622; ikona niewidoczna.
- `connected(ModemData)` — dane pobrane; ikona + pełne menu.
- `error(kind)` — WiFi jest, ale wystąpił problem; ikona widoczna, menu z komunikatem.

## Ikona i menu (wygląd)

**Ikona na pasku:** SF Symbol `cellularbars`, zmieniający się wg siły sygnału
(mała liczba kresek / `antenna.radiowaves.left.and.right.slash` przy braku sygnału,
pełne kreski przy dobrym). Kolor może subtelnie sygnalizować stan (np. czerwony
gdy bateria < 20%).

**Menu po kliknięciu:**

```
┌─────────────────────────────┐
│  ZTE U50 · ZTE_B4B622       │
├─────────────────────────────┤
│  🔋 Bateria      84%        │
│  📶 Sygnał       Bardzo dobry│
│  📡 Sieć         5G         │
│  📊 RSRP         -85 dBm    │
│      RSRQ        -10 dB     │
│      SINR        12 dB      │
│  🏢 Operator     Play       │
├─────────────────────────────┤
│  Odśwież teraz              │
│  Zakończ                    │
└─────────────────────────────┘
```

Pola RSRP/RSRQ/SINR pokazywane tylko jeśli modem je udostępnia
(do zweryfikowania na żywo).

## Obsługa błędów

- Brak WiFi ZTE_B4B622 → ikona znika (stan normalny, nie błąd).
- WiFi jest, modem nie odpowiada / timeout → menu: „⚠️ Nie można połączyć z modemem".
- Błąd logowania (złe hasło) → menu: „⚠️ Błąd logowania — sprawdź hasło".
- Brak uprawnień do lokalizacji → menu: „⚠️ Włącz uprawnienia lokalizacji,
  aby wykrywać sieć WiFi".

## Uprawnienia (CoreWLAN)

Odczyt SSID na nowszych macOS (Sonoma/Sequoia) wymaga uprawnienia
**Location Services** — Apple powiązało odczyt SSID z lokalizacją. Aplikacja
poprosi o zgodę na lokalizację przy pierwszym uruchomieniu.

## Konfiguracja

Adres IP modemu, hasło do panelu i nazwa SSID zaszyte na start w `Config.swift`
(proste, YAGNI). Hasło nie trafia do gita — plik z sekretem w `.gitignore`
albo wpis lokalny (do ustalenia przy implementacji).

## Testowanie

- `ModemClient` — testy parsowania odpowiedzi modemu na bazie realnego JSON
  (fixture z prawdziwej odpowiedzi).
- `WiFiMonitor` / logika stanów — testy przejść (hidden / connected / error).
- Ręczne: zbudowanie `.app`, uruchomienie, weryfikacja ikony i menu na żywo.

## Budowanie

SwiftPM + skrypt pakujący do `.app` (skill `macos-spm-app-packaging`).
Uruchamiane jednym poleceniem, bez Xcode.

## Krytyczny pierwszy krok implementacji

Przed napisaniem parsera — odpytać modem na żywo (curl / przeglądarka), by poznać
**dokładne endpointy i nazwy pól** (modele ZTE się różnią). To ustawia fundament
pod `ModemClient`.

## Poza zakresem (YAGNI)

- Konfiguracja przez GUI (ustawienia w pliku wystarczą na start).
- Historia / wykresy sygnału.
- Powiadomienia push.
- Obsługa wielu modemów.
