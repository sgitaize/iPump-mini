# ADR 0003: Auf OpenMinimed aufbauen, iOS neu entwickeln

- Status: **angenommen** (2026-10-14, Simon)
- Datum: 2026-10-14

## Kontext
Die Recherche in Phase 1 (`docs/landscape.md`) zeigt: Protokoll und SAKE-Krypto der 700er-Serie sind durch OpenMinimed (GPL-3.0) öffentlich verstanden und implementiert (Python, Java, PebbleOS-C). Eine iOS-Implementierung existiert nicht.

## Entscheidung
1. Wir schließen uns der OpenMinimed-Community an (Discord) und nutzen deren Dokumentation als Protokollquelle.
2. Wir bauen eine Swift-Portierung von PythonSake als eigenständiges Paket (GPL-3.0) und bieten sie upstream an.
3. Die iOS-App ist Neuentwicklung. Android folgt später auf Basis von JavaSake und in Abstimmung mit GlycemicGPT.
4. Kein `bleak`-Prototyp (bleak kann keine Peripheral-Rolle). Wir gehen direkt zu einem Swift-Spike, zuerst als macOS-CLI, dann auf dem iPhone. Eine Linux-Referenz mit PythonPumpConnector (z. B. Pi Zero 2 W) gibt es nur als Fallback, falls wir festhängen.
5. Die SAKE-Key-DB kommt nicht ins Repo. Sie wird lokal aus `_vendor/` bzw. einer Konfiguration geladen.

## Konsequenzen
- Die Lizenz wird faktisch GPL-3.0 (ADR 0002 ist anzupassen). Vertrieb für iOS per Selbst-Build oder TestFlight.
- Phase 2 schrumpft auf gezielte Fragen. Phase 3 konzentriert sich auf iOS-spezifisches Verhalten (PacketLogger-Mitschnitt der offiziellen iOS-App).
- Größte Risiken: Hintergrund-Reconnect unter iOS (FE81-Advertising im Hintergrund), GATT-Client-Zugriff auf eine eingehende Verbindung, MTU-Verhalten.
