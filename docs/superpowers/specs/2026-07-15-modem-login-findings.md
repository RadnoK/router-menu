# ZTE U50 — logowanie i liczniki transferu (na żywo, 2026-07-15)

Modem: ZTE U50, firmware `wa_inner_version = BD_STDPLU50V1.0.0B03`.

## Kluczowe odkrycie

Liczniki transferu (łączny, miesięczny) są **puste bez zalogowania**. Po
zalogowaniu zwracają pełne dane. Bieżąca przepustowość (`realtime_*_thrpt`)
działa BEZ logowania.

## Algorytm logowania (zweryfikowany na żywo — result:0)

1. `GET goform_get_cmd_process?cmd=LD` → zwraca `LD` (64 hex znaki, token).
2. Policz hash hasła:
   ```
   password = SHA256( SHA256(hasło).hex.upper() + LD ).hex.upper()
   ```
   (Podwójny SHA256: najpierw samo hasło, potem konkatenacja z LD, wynik UPPERCASE.)
3. `POST goform_set_cmd_process` z body (form-urlencoded):
   ```
   isTest=false&goformId=LOGIN&password=<hash>
   ```
   Nagłówek `Referer: http://192.168.0.1/`.
4. Odpowiedź sukcesu: `{"result":"0"}`. Sesja utrzymywana przez cookie **`stok`**.

`login_lock_time` = -1 (brak blokady). Po kilku błędnych próbach modem może
tymczasowo blokować — obsłużyć `result != "0"` jako błąd logowania.

## Pola transferu (po zalogowaniu, z cookie stok)

| Pole                  | Przykład         | Znaczenie |
|-----------------------|------------------|-----------|
| `realtime_rx_bytes`   | `1008395299`     | Sesja: pobrane (bajty) |
| `realtime_tx_bytes`   | `1850536546`     | Sesja: wysłane (bajty) |
| `realtime_rx_thrpt`   | `6149`           | Bieżąca prędkość pobierania (B/s) — BEZ logowania |
| `realtime_tx_thrpt`   | `60709`          | Bieżąca prędkość wysyłania (B/s) — BEZ logowania |
| `total_rx_bytes`      | `111604507190`   | Łącznie pobrane (bajty, ~104 GB) |
| `total_tx_bytes`      | `22997555141`    | Łącznie wysłane (bajty) |
| `monthly_rx_bytes`    | `20248857403`    | Miesiąc: pobrane (bajty) |
| `monthly_tx_bytes`    | `3998344877`     | Miesiąc: wysłane (bajty) |
| `realtime_time`       | `7100`           | Czas trwania sesji (sekundy) |
| `monthly_time`        | `127070`         | Czas połączenia w miesiącu (sekundy) |
| `total_connected_time`| `""`             | Puste na tym firmware — nie używać |

Wszystkie wartości to stringi z liczbą bajtów. GB = bajty / 1024³.

## Implikacje dla aplikacji

- **Logowanie opcjonalne**: aplikacja działa bez hasła (bateria, sygnał, sieć,
  prędkość transferu). Hasło potrzebne TYLKO dla liczników total/monthly.
- Hasło przechowywać w **Keychain** (nie w pliku, nie w gicie).
- Klient utrzymuje sesję (cookie `stok`); przy `result != 0` / wygaśnięciu
  sesji — ponowne logowanie.
- Uptime sesji: `realtime_time` (sekundy). Miesięczny: `monthly_time`.
