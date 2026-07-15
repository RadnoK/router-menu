# ZTE U50 — weryfikacja API (na żywo, 2026-07-15)

Modem: ZTE U50 5G, operator T-Mobile.pl, SSID `ZTE_B4B622`.

## Kluczowe odkrycie

**Dane statusu są dostępne BEZ logowania.** Nie trzeba się uwierzytelniać
ani podawać hasła — zwykły HTTP GET wystarcza. To znacząco upraszcza `ModemClient`
(brak logowania / sesji / cookies).

## Panel

- IP: `http://192.168.0.1`
- `/` → 302 → `/index.html`
- Endpoint danych: `GET /goform/goform_get_cmd_process`
  - Query: `isTest=false&cmd=<pola oddzielone przecinkiem>&multi_data=1`
  - Nagłówek `Referer: http://192.168.0.1/` — podawany dla pewności (działa też bez).
  - Odpowiedź: JSON `{"pole":"wartość", ...}` (wszystkie wartości jako stringi).

## Pola używane przez aplikację

| Pole              | Przykład            | Znaczenie |
|-------------------|---------------------|-----------|
| `battery_value`   | `"60"`              | Bateria w % (0–100) |
| `battery_charging`| `"0"`               | 0 = nie ładuje, 1 = ładuje |
| `battery_pers`    | `"3"`               | (poziom baterii w skali słupków; pomocnicze) |
| `signalbar`       | `"5"`               | Siła sygnału 0–5 (główny wskaźnik do ikony) |
| `network_type`    | `"ENDC"`            | Typ sieci (patrz mapowanie niżej) |
| `network_provider`| `"T-Mobile.pl"`     | Operator |
| `ppp_status`      | `"ppp_connected"`   | Status połączenia z internetem |
| `modem_main_state`| `"modem_init_complete"` | Stan modemu |
| `Z5g_rsrp`        | `"-81"`             | RSRP 5G w dBm (im bliżej 0, tym lepiej) |
| `Z5g_SINR`        | `"33.0"`            | SINR 5G w dB (jakość sygnału) |

### Pola PUSTE na tym modemie/sieci (nie używać)

`rssi`, `rscp`, `rsrp`, `rsrq`, `rscp`, `ecio`, `sinr`, `lte_rsrp`, `lte_rsrq`,
`lte_rssi`, `lte_snr`, `nr5g_pci`, `nr5g_action_band`, `cell_id`,
`wan_active_band`, `wan_active_channel`, `rmcc`, `rmnc`.

W sieci 5G (ENDC) wypełnione są tylko pola `Z5g_*`. Aplikacja musi tolerować
puste stringi (parser: pusty string → wartość nieznana, pole ukryte w menu).

## Mapowanie `network_type`

- `ENDC` → **5G** (EN-DC = LTE + 5G NSA; wyświetlamy jako „5G")
- inne możliwe wartości (LTE, LTE_CA, WCDMA…) — mapować na czytelne etykiety;
  nieznane → pokazać surową wartość.

## Mapowanie `signalbar` (0–5) na ikonę `cellularbars`

- 0 → brak / `antenna.radiowaves.left.and.right.slash`
- 1–5 → `cellularbars` z odpowiednim wypełnieniem (SF Symbol wspiera warianty
  wypełnienia słupków przez `variableValue: Double(signalbar)/5.0`).

## Przykładowe surowe odpowiedzi (fixture do testów)

Status:
```json
{"network_type":"ENDC","signalbar":"5","battery_value":"60","battery_charging":"0","battery_pers":"3","ppp_status":"ppp_connected","network_provider":"T-Mobile.pl","modem_main_state":"modem_init_complete"}
```

Sygnał 5G:
```json
{"signalbar":"5","network_type":"ENDC","Z5g_rsrp":"-81","Z5g_SINR":"33.0"}
```

## Wpływ na projekt

- **Usuwamy logowanie** z `ModemClient` — nie ma hasła w Config.
- `Config.swift` zawiera tylko: IP modemu (`192.168.0.1`) i nazwę SSID (`ZTE_B4B622`).
- Menu: pokazujemy Bateria, Sygnał (signalbar + RSRP/SINR jeśli niepuste),
  Sieć (mapowane `network_type`), Operator.
