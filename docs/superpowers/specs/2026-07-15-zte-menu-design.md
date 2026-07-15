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

- **`ModemClient`** — komunikacja z modemem ZTE: pobieranie surowych danych
  (bateria, sygnał, typ sieci, operator) przez wewnętrzne API
  `GET /goform/goform_get_cmd_process`. **Bez logowania** — zweryfikowano na żywo,
  że dane statusu są dostępne bez uwierzytelniania (patrz
  `2026-07-15-modem-api-findings.md`).
- **`WiFiMonitor`** — sprawdza aktualne SSID przez CoreWLAN; decyduje o widoczności ikony.
- **`ModemStore`** — stan aplikacji (`@Observable`): aktualne dane, status
  połączenia, timer odświeżania co 60 s. Spina `WiFiMonitor` + `ModemClient`.
- **`MenuBarView`** — SwiftUI: ikona na pasku + rozwijane menu ze szczegółami.
- **`App` / `AppDelegate`** — punkt wejścia, `MenuBarExtra`, konfiguracja LSUIElement.
- **`Config.swift`** — konfiguracja: adres IP modemu (`192.168.0.1`) i nazwa SSID
  (`ZTE_B4B622`). Bez hasła — dane dostępne bez logowania.

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
- Brak uprawnień do lokalizacji → menu: „⚠️ Włącz uprawnienia lokalizacji,
  aby wykrywać sieć WiFi".

(Błąd logowania nie występuje — dane dostępne bez uwierzytelniania.)

## Uprawnienia (CoreWLAN)

Odczyt SSID na nowszych macOS (Sonoma/Sequoia) wymaga uprawnienia
**Location Services** — Apple powiązało odczyt SSID z lokalizacją. Aplikacja
poprosi o zgodę na lokalizację przy pierwszym uruchomieniu.

## Konfiguracja

Adres IP modemu (`192.168.0.1`) i nazwa SSID (`ZTE_B4B622`) zaszyte w `Config.swift`
(proste, YAGNI). Bez hasła — dane statusu dostępne bez logowania (zweryfikowano na żywo).

## Testowanie

- `ModemClient` — testy parsowania odpowiedzi modemu na bazie realnego JSON
  (fixture z prawdziwej odpowiedzi).
- `WiFiMonitor` / logika stanów — testy przejść (hidden / connected / error).
- Ręczne: zbudowanie `.app`, uruchomienie, weryfikacja ikony i menu na żywo.

## Budowanie

SwiftPM + skrypt pakujący do `.app` (skill `macos-spm-app-packaging`).
Uruchamiane jednym poleceniem, bez Xcode.

## Weryfikacja API (wykonana)

API modemu zostało już odpytane na żywo — dokładne endpointy, nazwy pól i przykładowe
odpowiedzi (fixtures) są udokumentowane w `2026-07-15-modem-api-findings.md`.
Najważniejsze: dane dostępne bez logowania; pola sygnału 5G to `Z5g_rsrp` i `Z5g_SINR`;
siła sygnału `signalbar` (0–5); `network_type=ENDC` → „5G".

## Poza zakresem (YAGNI)

- Konfiguracja przez GUI (ustawienia w pliku wystarczą na start).
- Historia / wykresy sygnału.
- Powiadomienia push.
- Obsługa wielu modemów.
