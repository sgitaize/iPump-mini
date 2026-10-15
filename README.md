# iPump-mini

*Project and repository name: openMinipump.*

**→ [Get started](docs/getting-started.md)** (Deutsch / English)

**English summary.** An open-source iPhone app that reads a Medtronic MiniMed 780G insulin pump **strictly read-only** over Bluetooth LE, without the manufacturer cloud. It shows sensor glucose, insulin on board, reservoir, SmartGuard state and the pump history (boluses, auto corrections, carbs, calibrations). Optionally it uploads to your own Nightscout and serves a local Nightscout-compatible API. It builds on the protocol research of [OpenMinimed](https://github.com/OpenMinimed). Not a medical device, not affiliated with Medtronic, not for treatment decisions.

---

Eine quelloffene iPhone-App, die eine Insulinpumpe der Reihe **MiniMed 780G ausschließlich lesend** per Bluetooth LE ausliest, ohne Hersteller-Cloud.

> ⚠️ **Wichtig**
>
> - **Nicht für Therapieentscheidungen.** Die angezeigten Daten können falsch, veraltet oder unvollständig sein. Maßgeblich sind immer die Anzeigen und Alarme der Pumpe.
> - **Kein Medizinprodukt**, keine Zulassung, keine CE-Kennzeichnung.
> - **Keine Verbindung zum Hersteller.** Medtronic, MiniMed, CareLink, SmartGuard, Guardian und Simplera sind Marken ihrer Inhaber. Das Projekt wird von ihnen weder unterstützt noch geprüft.
> - **Nur lesend.** Die App sendet keine Befehle, die Therapie, Einstellungen oder Zustand der Pumpe verändern. Das ist im Code durch eine Allowlist erzwungen (`core/MiniMedKit/Sources/MiniMedKit/Safety/ReadOnlyPolicy.swift`).
> - Nutzung auf eigenes Risiko.

## Was die App kann

- **Live-Werte** alle 5 Minuten, auch im Hintergrund: Sensorwert mit Trend, aktives Insulin, Reservoir, Pumpenbatterie, Modus (SmartGuard/Manuell), Basal, Zeit im Zielbereich, Sensorstatus und Sensorablauf.
- **Pumpenhistorie:** Boli, SmartGuard-Autokorrekturen, Auto-Basal, Kohlenhydrate, BZ-Messungen und Kalibrierungen, Pausen. Fehlende Sensorwerte werden aus der Pumpe nachgetragen.
- **Graph** (3/6/12/24 h) mit Mahlzeiten, Boli und Insulin-Band. Antippen eines Werts oder Zeitblocks zeigt Details (Uhrzeit, Wert, aktives Insulin, Abgaben).
- **Nightscout-Upload** (optional): Werte sofort bei neuem Wert, Pumpenstatus, Behandlungen.
- **Lokale API** im Nightscout-Format auf Port 17580 (wie xDrip+), inkl. `/pebble` und einer Statusseite mit Passwort; optional im WLAN.
- **Alarme:** dringend niedrig, niedrig, hoch, schnelle Änderungen, Meldungen der Pumpe, „keine Daten“, mit Stummschalten und Voreinstellungen.
- **Widgets** (Home- und Sperrbildschirm) und **Live-Aktivität/Dynamic Island**.
- **Deutsch und Englisch**, hell/dunkel, mg/dL oder mmol/L, eigener Zielbereich.
- **Ersteinrichtung** mit Nutzungsbedingungen, Checkliste und Anleitung in der App.

## Wie es funktioniert

Die Pumpe ist der Bluetooth-Central, das iPhone der Peripheral. Nach der Kopplung baut die Pumpe die Verbindung auf und handelt mit der App eine verschlüsselte Sitzung aus (Medtronic-Protokoll „SAKE“). Die App liest dann über dieselbe Verbindung die Bluetooth-Standarddienste der Pumpe (Insulin Delivery Service, CGM Service) mit Medtronic-Erweiterungen.

Das Protokollwissen stammt aus der Arbeit von **[OpenMinimed](https://github.com/OpenMinimed)** (GPL-3.0). Die Verschlüsselung in `core/MiniMedKit` ist ein Swift-Port von deren PythonSake/JavaSake und wird gegen einen echten 780G-Mitschnitt getestet. Details: [`docs/landscape.md`](docs/landscape.md), [`docs/lab-notebook.md`](docs/lab-notebook.md).

## Selbst bauen

Voraussetzungen: Mac mit Xcode, [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`), ein iPhone und eine Apple-ID (das kostenlose Entwickler-Team genügt; die App läuft dann jeweils 7 Tage).

1. **Repository klonen**, dann `git config core.hooksPath .githooks` (Secret-Scan vor jedem Commit, braucht `gitleaks`).
2. **Schlüsseldatenbank:** Die App braucht die SAKE-Schlüsseldatenbank „Mobile Application ↔ Insulin Pump“. Sie ist **nicht** in diesem Repository. Am einfachsten lädt die App sie selbst aus der [OpenMinimed-Dokumentation](https://github.com/OpenMinimed/Documentation/blob/main/key_databases.md) (Ersteinrichtung bzw. Einstellungen › Pumpe › Schlüsseldatenbank). Für eigene Builds kannst du sie stattdessen als eine Zeile Hex in `_vendor/keys/mobile-pump.keydb.hex` ablegen (Ordner ist gitignored); dann wird sie ins App-Paket übernommen.
3. **`.env`** aus `.env.example` anlegen. Im Entwicklermodus (`DEV_MODE=1`) akzeptiert die App nur die Pumpe mit der Seriennummer aus `TEST_PUMP_SERIAL`.
4. **Signing:** `apps/ios/Config/Local.xcconfig.example` nach `Local.xcconfig` kopieren und `DEVELOPMENT_TEAM` eintragen. Mit dem kostenlosen Team eine eigene `OMP_BUNDLE_ID` wählen. Das kostenlose Team kann App Groups (Standard), aber keine zeitkritischen Mitteilungen; mit bezahltem Account `OMP_APP_ENTITLEMENTS = OpenMinipump/OpenMinipump-paid.entitlements`. Beim ersten Build mit neuer Berechtigung einmal in Xcode starten (⌘R), damit Xcode das Profil holt.
5. **Bauen:** `cd apps/ios && xcodegen && open OpenMinipump.xcodeproj`, iPhone wählen, starten. Auf dem iPhone den Entwicklermodus aktivieren (Einstellungen › Datenschutz & Sicherheit).
6. **Koppeln:** Ist die offizielle MiniMed-Mobile-App gekoppelt, diese Kopplung an der Pumpe entfernen (die Pumpe nimmt nur ein Mobilgerät an). Dann in der App „Pumpe koppeln“ öffnen und der Anleitung folgen.

Tests der Protokoll-Bibliothek: `cd core/MiniMedKit && swift test`. Ausführlicher: [`docs/setup-ios.md`](docs/setup-ios.md), API: [`docs/api.md`](docs/api.md).

## Grenzen

- iOS pausiert die App im Hintergrund zwischen den Pumpen-Updates. Die lokale API antwortet dann nicht; für Uhren und andere Geräte ist der Nightscout-Upload zuverlässiger.
- Wird die App weggewischt, kommen keine Daten mehr. Die App erinnert per Mitteilung daran, sie wieder zu öffnen.
- Kritische Alarme (durch den Stummschalter) erfordern eine Apple-Freigabe; ohne sie sind Alarme „zeitkritisch“.
- Getestet mit einer 780G (Firmware 6.23W) und Simplera Sync.

## Struktur

```
core/MiniMedKit/   Swift-Paket: SAKE, Protokoll-Parser, Allowlist, Nightscout-Format, Tests
apps/ios/          SwiftUI-App, Widgets (XcodeGen: project.yml)
docs/              Recherche, Entscheidungen (ADRs), Laborbuch, API, Aufgaben
research/          eigene Analyse-Skripte
captures/, _vendor/  gitignored: Mitschnitte, Schlüssel, Fremdmaterial
```

## Rechtsrahmen

Reverse Engineering ausschließlich zur Herstellung der Interoperabilität mit dem eigenen Gerät (Art. 6 RL 2009/24/EG, § 69e UrhG) und Datenzugang nach dem EU Data Act (VO (EU) 2023/2854). Das Repository enthält nur eigenen Code und eigene Beschreibungen (Clean Room), keinen Code und keine Assets des Herstellers.

## Lizenz

GPL-3.0, siehe [LICENSE](LICENSE) und [ADR 0002](docs/decisions/0002-lizenz.md). Dank an [OpenMinimed](https://github.com/OpenMinimed), [Nightscout](https://github.com/nightscout/cgm-remote-monitor) und [xDrip+](https://github.com/NightscoutFoundation/xDrip).
