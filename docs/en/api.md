# Local API (Nightscout-compatible)

*Deutsch: [api.md](../de/api.md)*

The app serves the data it reads through a small HTTP server. It uses the same paths and JSON shapes as Nightscout API v1, so existing clients (watchfaces, widgets) work without changes.

- **Port:** `17580`, like the local web server of xDrip+.
- **Default:** reachable only on the iPhone itself (`http://127.0.0.1:17580`).
- **Wi-Fi (optional):** enable it in the settings. An API secret is then required: header `api-secret` (plain or SHA-1 hex, as in Nightscout), `?token=<secret>` or Basic Auth with the secret as password. Requests from the iPhone itself need no secret.
- **Read-only:** everything except `GET`/`HEAD` returns `405`.
- **Status page:** `/status.html` (or `/` in a browser) shows value, trend, pump status and recent values and reloads every minute. Protected by Basic Auth (any user name, password = API secret). Note: on Wi-Fi this is plain HTTP.
- **Stability:** iOS takes the sockets away from suspended apps. The server restarts itself after errors (backoff up to 30 s) and when the app is opened.

## Endpoints

| Path | Content |
|---|---|
| `/api/v1/entries.json?count=N` (also `/api/v1/entries/sgv.json`, `/sgv.json`) | Sensor values, newest first (default 10). Filter `find[date][$gte\|$gt\|$lte\|$lt]=<ms>` |
| `/api/v1/entries/current.json` | Latest sensor value |
| `/api/v1/devicestatus.json` | Pump status: `pump.reservoir`, `pump.iob.iob`, `pump.battery.percent`, `pump.status.suspended`, `pump.extended` (mode, basal rate, TIR, transmitter, sensor expiry), `uploaderBattery` |
| `/api/v1/treatments.json?count=N` | Treatments from the pump history: boluses, SmartGuard auto corrections, carbs, BG checks, calibrations, basal changes, suspend/resume |
| `/api/v1/status.json` | Server status, unit mg/dl |
| `/pebble?count=N&units=mmol` | Classic Pebble endpoint (`bgs[].sgv`, `trend`, `direction`, `bgdelta`, `iob`, `battery`) |

### Example entry

```json
{"_id":"omp-1792012800000","type":"sgv","sgv":123,"direction":"SingleDown","trend":6,
 "date":1792012800000,"dateString":"2026-10-14T21:20:00.000Z","device":"openMinipump",
 "trendRate":-1.2,"utcOffset":120}
```

### Trend arrows
The pump reports a rate of change in mg/dL/min. Medtronic shows one arrow from 1, two from 2 and three from 3 mg/dL/min. For Nightscout: below 1 is `Flat`, from 1 `SingleUp`/`SingleDown`, from 2 `DoubleUp`/`DoubleDown`. Three arrows also map to `Double*`, because not every client knows `TripleUp`. The raw rate is in `trendRate`.

### Wake schedule (`ompSync`)
`/pebble` additionally returns when the app is reachable in the background (other clients ignore the field):

```json
"ompSync": {"lastWake": 1792012800000, "nextWake": 1792013100000, "intervalSec": 300, "windowSec": 25}
```
`lastWake`/`nextWake` are ms since 1970 (server clock, compare with `status[0].now`). The pump wakes the app about every 5 minutes (`intervalSec`, learned from recent wake-ups); after each wake the server stays reachable for about `windowSec`. Clients should poll just after `nextWake` instead of continuously.

## Limitation on iOS
In the background, iOS keeps the app awake only while it handles a Bluetooth event (the pump reports about every 5 minutes). In between, the app is suspended and **the server does not answer**. The API is reliable while the app is in the foreground.

For continuous use, the **Nightscout upload** is the better choice: it runs with every Bluetooth event, also in the background.
