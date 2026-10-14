# iOS-App bauen und aufs iPhone bringen

## Voraussetzungen
- Xcode, XcodeGen (`brew install xcodegen`)
- Im Repo-Root eine `.env` mit `DEV_MODE=1` und `TEST_PUMP_SERIAL=…` (siehe `.env.example`)
- Die SAKE-Schlüsseldatenbank als Hex in `_vendor/keys/mobile-pump.keydb.hex` (gitignored). Inhalt: der Eintrag „Mobile Application ↔ Insulin Pump“ aus der OpenMinimed-Dokumentation (`Documentation/key_databases.md`), eine Zeile Hex.

Beides wird beim Build vom Skript `apps/ios/Scripts/embed-local-config.sh` ins App-Bundle kopiert und nie committet. Fehlt `.env`, gilt `DEV_MODE=1` ohne Testpumpe: Die App lehnt dann jede Pumpe ab.

## Signing
1. Xcode › Settings › Accounts: Apple-ID anmelden (das kostenlose persönliche Team reicht, die App läuft dann 7 Tage).
2. `apps/ios/Config/Local.xcconfig.example` nach `Local.xcconfig` kopieren und `DEVELOPMENT_TEAM` eintragen. Mit kostenlosem Team zusätzlich eine eigene `OMP_BUNDLE_ID` setzen.

## Bauen
```sh
cd apps/ios
xcodegen            # erzeugt OpenMinipump.xcodeproj (gitignored)
open OpenMinipump.xcodeproj
```
Dann in Xcode das iPhone als Ziel wählen und starten. Auf dem iPhone muss der Entwicklermodus aktiv sein (Einstellungen › Datenschutz & Sicherheit › Entwicklermodus).

Tests der Protokoll-Bibliothek: `cd core/MiniMedKit && swift test`.
