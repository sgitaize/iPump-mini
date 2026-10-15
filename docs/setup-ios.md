# iPump-mini selbst bauen

*English: [building.md](building.md)*

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

Tests der Protokoll-Bibliothek: `cd core/MiniMedKit && swift test`.
