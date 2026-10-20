<p align="center">
  <img src="apps/ios/OpenMinipump/Assets.xcassets/AppIcon.appiconset/AppIcon.png" width="96" alt="iPump-mini Icon">
</p>

<h1 align="center">iPump-mini</h1>

<p align="center">
  Eine quelloffene iPhone-App, die eine Insulinpumpe <b>MiniMed 780G ausschließlich lesend</b> per Bluetooth ausliest – ohne Hersteller-Cloud.<br>
  <a href="docs/de/erste-schritte.md"><b>Erste Schritte</b></a> · <a href="docs/de/selbst-bauen.md">Selbst bauen</a> · <a href="README.md">English</a>
</p>

<p align="center">
  <img src="docs/images/home-light.png" width="230" alt="Startseite">
  <img src="docs/images/home-dark.png" width="230" alt="Startseite, dunkel">
  <img src="docs/images/widgets.png" width="230" alt="Widgets">
</p>

> [!WARNING]
> **Kein Medizinprodukt. Nicht für Therapieentscheidungen.** Werte können falsch, verspätet oder unvollständig sein. Maßgeblich sind immer die Anzeigen und Alarme der Pumpe; die bleiben eingeschaltet. Keine Verbindung zu Medtronic. Nutzung auf eigenes Risiko.

## Funktionen
- **Live-Werte alle 5 Minuten, auch im Hintergrund:** Sensorwert mit Trend, aktives Insulin, Reservoir, Pumpenbatterie, SmartGuard-Status, Basal, Zeit im Zielbereich, Sensorstatus und -ablauf.
- **Pumpenhistorie:** Boli, SmartGuard-Autokorrekturen, Auto-Basal, Kohlenhydrate, BZ-Messungen und Kalibrierungen, Pausen. Lücken in der Sensorkurve werden aus der Pumpe nachgetragen.
- **Graph** (3/6/12/24 h) mit Behandlungen und Insulin-Band. Antippen oder seitlich wischen zeigt Details (Uhrzeit, Wert, aktives Insulin, Abgaben).
- **Alarme:** dringend niedrig, niedrig, hoch, schnelle Änderungen, Pumpenmeldungen, „keine Daten“, mit Stummschalten und Voreinstellungen.
- **Widgets** für Home- und Sperrbildschirm, **Live-Aktivität / Dynamic Island**.
- **Nightscout-Upload** (optional) und **lokale Nightscout-kompatible API** auf Port 17580 (inkl. `/pebble`).
- **Deutsch und Englisch**, hell/dunkel, mg/dL oder mmol/L, eigener Zielbereich.
- **Ersteinrichtung** mit Nutzungsbedingungen, Checkliste und Anleitung in der App.
- **Android-Version** (Vorschau, noch ohne Hardwaretest): [docs/de/android.md](docs/de/android.md).

## Nur lesend – technisch erzwungen
Die App sendet keine Befehle, die Therapie, Einstellungen oder Zustand der Pumpe verändern. Jeder Schreibzugriff läuft über eine einzige Funktion und eine Allowlist von Abfragen ([`ReadOnlyPolicy.swift`](core/MiniMedKit/Sources/MiniMedKit/Safety/ReadOnlyPolicy.swift)); alles andere wird blockiert und protokolliert. Insulin abgeben oder Alarme quittieren kann sie nicht.

## Installieren
- **AltStore / SideStore:** in Vorbereitung.
- **Selbst bauen** mit Mac, Xcode und kostenloser Apple-ID: [docs/de/selbst-bauen.md](docs/de/selbst-bauen.md).

Danach den [ersten Schritten](docs/de/erste-schritte.md) folgen: Nutzungsbedingungen, Schlüsseldatenbank laden, Mitteilungen erlauben, Pumpe koppeln.

## Wie es funktioniert
Die Pumpe ist der Bluetooth-Central, das iPhone der Peripheral. Nach der Kopplung baut die Pumpe die Verbindung auf und handelt mit der App eine verschlüsselte Sitzung aus (Medtronic-Protokoll „SAKE“). Über dieselbe Verbindung liest die App die Bluetooth-Standarddienste der Pumpe (Insulin Delivery Service, CGM Service) mit Medtronic-Erweiterungen. Die Sitzung wird gespeichert; Updates und Neustarts brauchen keine neue Kopplung.

Das Protokollwissen stammt von **[OpenMinimed](https://github.com/OpenMinimed)** (GPL-3.0). Die SAKE-Implementierung in `core/MiniMedKit` ist ein Swift-Port von PythonSake/JavaSake und wird gegen einen echten 780G-Mitschnitt getestet. Die SAKE-Schlüsseldatenbank ist **nicht** im Repository und nicht in der App; die App lädt sie auf Wunsch aus der öffentlichen OpenMinimed-Dokumentation.

## Grenzen
- iOS pausiert die App zwischen den Pumpen-Updates; die lokale API antwortet dann nicht. Für Uhren ist der Nightscout-Upload zuverlässiger.
- Wird die App weggewischt, kommen keine Daten mehr. Eine Mitteilung erinnert daran.
- Kritische Alarme (durch den Stummschalter) brauchen eine Apple-Freigabe, zeitkritische einen bezahlten Entwickler-Account. Sonst sind Alarme normale Mitteilungen – die App im Schlaf-Fokus erlauben.
- Getestet mit einer 780G (Firmware 6.23W) und Simplera Sync.

## Repository
```
apps/ios/          SwiftUI-App und Widgets (XcodeGen: project.yml)
core/MiniMedKit/   Swift-Paket: SAKE, Protokoll-Parser, Allowlist, Nightscout-Format, Tests
docs/              en/ und de/: Anleitungen und API · internal/: Arbeitsnotizen (Deutsch)
research/          eigene Analyse-Skripte
```
Mehr: [Dokumentation](docs/README.md) · [API](docs/de/api.md) · [Arbeitsnotizen](docs/internal/README.md) (Laborbuch, Recherche, Entscheidungen)

## Rechtsrahmen
Reverse Engineering ausschließlich zur Herstellung der Interoperabilität mit dem eigenen Gerät (Art. 6 RL 2009/24/EG, § 69e UrhG) und Datenzugang nach dem EU Data Act (VO (EU) 2023/2854). Das Repository enthält nur eigenen Code und eigene Beschreibungen (Clean Room) – keinen Code, keine Schlüssel und keine Assets des Herstellers. MiniMed, SmartGuard, Guardian, Simplera und CareLink sind Marken ihrer Inhaber.

## Lizenz und Dank
GPL-3.0, siehe [LICENSE](LICENSE) und [ADR 0002](docs/internal/decisions/0002-lizenz.md). Dank an [OpenMinimed](https://github.com/OpenMinimed), [Nightscout](https://github.com/nightscout/cgm-remote-monitor) und [xDrip+](https://github.com/NightscoutFoundation/xDrip).

Von [Simon Gutjahr](https://simongutjahr.de/dev/) · [Impressum](https://simongutjahr.de/impressum/)
