# Lokale API (Nightscout-kompatibel)

Die iOS-App stellt die gelesenen Daten über einen kleinen HTTP-Server bereit. Er spricht dieselben Pfade und JSON-Formen wie Nightscout API v1, sodass vorhandene Clients (Watchfaces, Widgets, supercgm) ohne Änderung funktionieren sollen.

- **Port:** `17580`, wie der lokale Webserver von xDrip+.
- **Standard:** nur auf dem iPhone selbst erreichbar (`http://127.0.0.1:17580`).
- **WLAN (optional):** in den Einstellungen freigeben. Dann ist ein API-Secret Pflicht: Header `api-secret` (Klartext oder SHA-1-Hex wie bei Nightscout) oder `?token=<secret>`. Anfragen vom iPhone selbst brauchen kein Secret.
- **Nur lesen:** Alles außer `GET`/`HEAD` liefert `405`.
- **Startseite für Menschen:** `/status.html` (oder `/` im Browser) zeigt Wert, Trend, Pumpenstatus und die letzten Werte, lädt jede Minute neu. Schutz per **Basic Auth**: Benutzername beliebig, Passwort = API-Secret. Ohne gesetztes Secret nur auf dem iPhone selbst erreichbar. Achtung: Im WLAN läuft das unverschlüsselt (HTTP).
- **Basic Auth** mit dem Secret als Passwort funktioniert auch für die JSON-Endpunkte.
- **Stabilität:** iOS entzieht pausierten Apps die Server-Sockets. Der Server startet nach Fehlern selbst neu (Backoff bis 30 s) und beim Öffnen der App.

## Endpunkte

| Pfad | Inhalt |
|---|---|
| `/api/v1/entries.json?count=N` (auch `/api/v1/entries/sgv.json`, `/sgv.json`) | Sensorwerte, neueste zuerst (Standard 10). Filter `find[date][$gte\|$gt\|$lte\|$lt]=<ms>` |
| `/api/v1/entries/current.json` | letzter Sensorwert |
| `/api/v1/devicestatus.json` | Pumpenstatus: `pump.reservoir`, `pump.iob.iob`, `pump.battery.percent`, `pump.status.suspended`, `pump.extended` (Modus, Basalrate, TIR, Transmitter, Sensorablauf), `uploaderBattery` |
| `/api/v1/treatments.json` | vorerst leer `[]` (kommt mit der IDD-History) |
| `/api/v1/status.json` | Serverstatus, Einheit mg/dl |
| `/pebble` | klassischer Pebble-Endpunkt (`bgs[0].sgv`, `trend`, `direction`, `bgdelta`, `iob`, `battery`) |

### Beispiel-Eintrag

```json
{"_id":"omp-1792012800000","type":"sgv","sgv":123,"direction":"SingleDown","trend":6,
 "date":1792012800000,"dateString":"2026-10-14T21:20:00.000Z","device":"openMinipump",
 "trendRate":-1.2,"utcOffset":120}
```

### Trendpfeile

Die Pumpe liefert eine Änderungsrate in mg/dL/min. Medtronic zeigt einen Pfeil ab 1, zwei ab 2 und drei ab 3 mg/dL/min. Für Nightscout gilt: unter 1 ist `Flat`, ab 1 `SingleUp`/`SingleDown`, ab 2 `DoubleUp`/`DoubleDown`. Drei Pfeile werden ebenfalls `Double*`, weil nicht alle Clients `TripleUp` kennen. Die Rohrate steht in `trendRate`.

## Grenze unter iOS

iOS hält die App im Hintergrund nur wach, solange ein Bluetooth-Ereignis verarbeitet wird (Pumpe meldet sich etwa alle 5 min). Dazwischen ist die App pausiert und **der Server antwortet nicht**. Verlässlich funktioniert die API, solange die App im Vordergrund ist.

Für den Dauerbetrieb ist deshalb der **Upload zu Nightscout** (Phase 4) der richtige Weg: Er läuft bei jedem Bluetooth-Ereignis mit, auch im Hintergrund.
