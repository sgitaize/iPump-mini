# iPump-mini selbst bauen

*English: [building.md](../en/building.md)*

## Voraussetzungen
- Xcode, XcodeGen (`brew install xcodegen`)
- Quellcode: `git clone https://github.com/sgitaize/iPump-mini.git`
- Im Repo-Root eine `.env` mit `DEV_MODE=1` und `TEST_PUMP_SERIAL=…` = Seriennummer **deiner** Pumpe (siehe `.env.example`)
- Optional: die SAKE-Schlüsseldatenbank als Hex in `_vendor/keys/mobile-pump.keydb.hex` (gitignored). Ohne Datei lädt die App sie beim ersten Start aus der [OpenMinimed-Dokumentation](https://github.com/OpenMinimed/Documentation/blob/main/key_databases.md).

Beides wird beim Build vom Skript `apps/ios/Scripts/embed-local-config.sh` ins App-Bundle kopiert und nie committet. Fehlt `.env`, gilt `DEV_MODE=1` ohne Testpumpe: Die App lehnt dann jede Pumpe ab.

## Signing
1. Xcode › Settings › Accounts: Apple-ID anmelden (das kostenlose persönliche Team reicht, die App läuft dann 7 Tage).
2. `apps/ios/Config/Local.xcconfig.example` nach `Local.xcconfig` kopieren und `DEVELOPMENT_TEAM` eintragen. Mit kostenlosem Team zusätzlich eine eigene `OMP_BUNDLE_ID` setzen.
3. Berechtigungen: Standard ist eine App Group (Widgets), die kann auch das kostenlose Team. Zeitkritische Mitteilungen nur mit bezahltem Team: `OMP_APP_ENTITLEMENTS = OpenMinipump/OpenMinipump-paid.entitlements`. Nach einer neuen Berechtigung einmal in Xcode mit ⌘R starten, damit das Profil erzeugt wird.

## Bauen
```sh
cd apps/ios
xcodegen            # erzeugt OpenMinipump.xcodeproj (gitignored)
open OpenMinipump.xcodeproj
```
Dann in Xcode das iPhone als Ziel wählen und starten. Auf dem iPhone muss der Entwicklermodus aktiv sein (Einstellungen › Datenschutz & Sicherheit › Entwicklermodus).

## Tests
Alles auf einmal (Protokoll-Bibliothek, dann iOS-Unit-Tests im Simulator):
```sh
apps/ios/Scripts/test.sh
```
Dauert etwa 20 s (beim ersten Mal länger wegen des Builds). Einzeln:
- `cd core/MiniMedKit && swift test` – Protokoll, Parser, Nightscout-Mapping, History, `ReadOnlyPolicy` und Plausibilitätschecks (Trendgrenzen, Zeitachse, Behandlungen).
- iOS: Target `OpenMinipumpTests` (läuft in der App als Host, Simulator „iPhone 17“, andere über `SIM_UDID=<udid>`). Abgedeckt sind `DataStore` (Dedupe, Aufbewahrung, Speichern), `AlarmEngine`, die lokale API (echter Server auf Port 17591, per URLSession abgefragt, inkl. `find[date][$gte]`), Einheiten und Deltas, Trendpfeile, Widget-Daten, Live-Activity-Kurve und die Demodaten. Plausibilitätschecks prüfen u. a. Werte 40–400 mg/dL, Lücken und Zukunftswerte, negative IOB, Sensorlaufzeit und die Feldnamen der Nightscout-Antworten.
- Bekannte Fehler stehen als `XCTExpectFailure` im Test, sie schlagen erst an, wenn der Fehler behoben ist.

Nicht abgedeckt: CoreBluetooth (`PumpLink`), SwiftUI-Ansichten, Widgets, Benachrichtigungen (es wird nur geprüft, ob ein Alarm ausgelöst würde) und die API-Anmeldung aus dem WLAN (Loopback braucht kein Secret). Beim Ändern der Allowlist (`ReadOnlyPolicy`) gelten weiter die Regeln aus `CLAUDE.md`.
