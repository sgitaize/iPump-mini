# ADR 0004: Android als native Kotlin-App mit eigenem Kotlin-Core

- Status: **vorgeschlagen** (2026-10-18, wartet auf Simons Go)
- Datum: 2026-10-18

## Kontext
Simon wünscht die App auch für Android. ADR 0003 sah dafür JavaSake vor (Maven Central) und eine Abstimmung mit GlycemicGPT. Die iOS-App ist inzwischen fertig. Ihr Protokollkern `core/MiniMedKit` (Swift) enthält mehr als SAKE: Parser inkl. History, Allowlist, DevModeGuard, Nightscout-Mapping und Alarmtabelle.

## Entscheidung
1. **Zwei native Implementierungen** statt Kotlin Multiplatform oder Rust. Der Swift-Core bleibt unverändert, `core/MiniMedKitKotlin/` ist eine 1:1-Portierung als reines JVM-Modul ohne Abhängigkeiten. Dieselben Testvektoren in beiden Sprachen sichern die Parität.
2. **Eigener SAKE-Port statt JavaSake-Abhängigkeit:** Der Port ist klein und folgt dem Swift-Code (Clean Room, GPL-3.0). Er läuft gegen denselben 780G-Trace wie JavaSake und PythonSake. Damit gibt es keine fremde Abhängigkeit im sicherheitskritischen Pfad.
3. **Allowlist doppelt, aber identisch:** `ReadOnlyPolicy.kt` spiegelt `ReadOnlyPolicy.swift`. Jede Änderung braucht Simons Freigabe und muss in beiden Dateien und Testsuiten gleich erfolgen.
4. **App-Architektur** wie auf iOS (`PumpLink`, `DataStore`, `AlarmEngine`, `LocalApiServer`, `NightscoutUploader`, Compose-UI). Ein **Vordergrunddienst** (`connectedDevice`) ersetzt die iOS-Hintergrundmodi.
5. Die GlycemicGPT- und JavaPumpConnector-Quellen dienten nur zum Abgleich von Fakten (Herstellerdaten im Advertising, GATT-Client auf derselben Verbindung). Es wurde kein Code übernommen.

## Konsequenzen
- Protokolländerungen (neue Parser, Allowlist) sind zweimal umzusetzen. Das ist bei der überschaubaren Größe (~1.000 Zeilen) vertretbar. Später kann man auf KMP umsteigen.
- CI (`.github/workflows/android.yml`) testet den Kotlin-Core und baut die App bei jeder Änderung.
- Hardwaretests mit der Testpumpe stehen noch aus (`docs/de/android.md`).
