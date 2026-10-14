# openMinipump

*Arbeitstitel, der Name kann sich noch ändern.*

Eine quelloffene iOS- und Android-App, die Daten einer Insulinpumpe der MiniMed-780G-Reihe **ausschließlich lesend** per Bluetooth LE ausliest und lokal über eine REST-API bereitstellt, ohne Abhängigkeit von einer Hersteller-Cloud.

> ⚠️ **Disclaimer**
>
> - **Nicht für Therapieentscheidungen.** Die angezeigten Daten können falsch, veraltet oder unvollständig sein. Maßgeblich sind immer die Pumpe selbst und die offizielle Hersteller-Software.
> - **Kein Medizinprodukt.** Dieses Projekt hat keine Zulassung oder Zertifizierung, insbesondere keine CE-Kennzeichnung nach MDR.
> - **Keine Verbindung zum Hersteller.** Medtronic, MiniMed und CareLink sind Marken ihrer jeweiligen Inhaber. Das Projekt ist weder von ihnen unterstützt noch mit ihnen verbunden.
> - **Nur lesend.** Das Projekt sendet keine Befehle, die Therapie, Einstellungen oder Zustand der Pumpe verändern. Das ist technisch über eine Allowlist erzwungen.
> - Nutzung auf eigenes Risiko.

## Rechtsrahmen

Reverse Engineering ausschließlich zur Herstellung der Interoperabilität (Art. 6 RL 2009/24/EG, § 69e UrhG) sowie das Datenzugangsrecht nach dem EU Data Act (VO (EU) 2023/2854) für das eigene Gerät. Das Repository enthält nur eigene Beschreibungen und eigenen Code (Clean Room), keinen Code und keine Assets des Herstellers.

## Struktur

```
docs/            Protokoll, Recherche, ADRs (docs/decisions), Laborbuch
research/        eigene Analyse-Skripte und Notizen (kein Vendor-Code)
captures/        gitignored: Roh-Mitschnitte (btsnoop, pcap, mitm)
_vendor/         gitignored: APK/IPA, Dekompilate, extrahiertes Material
proto/           Python-Referenzimplementierung (bleak), Replay-Tools
core/            gemeinsame Protokoll-Bibliothek für die Apps
apps/ios/        SwiftUI-App
apps/android/    Kotlin-App
```

## Setup

```sh
cp .env.example .env              # TEST_PUMP_SERIAL eintragen
git config core.hooksPath .githooks   # gitleaks-Pre-Commit-Hook aktivieren
```

## Lizenz

GPL-3.0, siehe [LICENSE](LICENSE) und [ADR 0002](docs/decisions/0002-lizenz.md).
