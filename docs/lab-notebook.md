# Laborbuch

Format: Datum · Was getestet · Ergebnis · Mitschnitt-Datei (in `captures/`, gitignored)

## 2026-10-14
- Phase 0 gestartet: Repo angelegt, Tools installiert. Noch keine Tests an der Pumpe.
- Phase 1 Recherche: Protokoll durch OpenMinimed geknackt, Pairing lokal ohne Cloud möglich. Siehe docs/landscape.md. Kein Test an der Pumpe.

## Testgerät
- MiniMed 780G, Seriennummer nur in `.env` (`TEST_PUMP_SERIAL`)
- Pumpen-Firmware: **6.23W (18.13.3)**, Stand 2026-10-14

## 2026-10-14 · Mitschnitt 1: Kopplung der offiziellen MiniMed Mobile (iOS)
- **Setup:** iPhone 18 Pro mit MiniMed Mobile (offiziell), PacketLogger über USB am Mac, Testpumpe (FW 6.23W)
- **Mitschnitt:** `captures/2026-10-14_2048_mmm-ios-pairing_pump1.pklg` (20:47:40–20:50:39). Auswertung mit `research/pklg_timeline.sh`. PacketLogger-Zeitstempel sind +2 h verschoben, das Skript korrigiert das.
- **Simons Notizen:** 20:48 Aufnahme gestartet · 20:49 „Mobile xxxxx“ auf der Pumpe angezeigt, Kopplungsanfrage auf dem iPhone bestätigt · 20:50 Kopplung abgeschlossen · danach kommen etwa alle 5 min Daten

### Ergebnisse
1. **Advertising der App** (Extended-Advertising-API, aber Legacy-PDUs, connectable und scannable, Random-Adresse/RPA):
   - Phase 1, vor dem Koppeln: Intervall 181 ms ohne erkennbare Service-UUID (vermutlich App-Start bzw. Apple-Standard)
   - 20:48:25: `0xFE81` + Name „Mobile 179728“, **Intervall 30 ms** (das ist der Reconnect-Modus, die App versucht es zuerst)
   - 20:48:54: Wechsel auf `0xFE82` + „Mobile 179728“, **30 ms** (Kopplungsmodus)
   - Beide UUIDs stehen **im Advertising selbst, nicht im Apple-Overflow-Bereich**. Die App war dabei im Vordergrund.
   - Die Ziffern im Namen sind zufällig bzw. von der App erzeugt (6 Ziffern).
2. **Verbindung:** Die Pumpe verbindet sich als Central, das iPhone hat die Rolle **Peripheral**. Die Pumpe nutzt eine öffentliche Adresse, das iPhone eine RPA. Verbindungsintervall 125 ms, Supervision-Timeout 3 s.
3. **BLE-Kopplung:** **Legacy Pairing** (kein Secure Connections). Die Pumpe hat IO-Capability *NoInputNoOutput*, das iPhone *KeyboardDisplay*. Daraus folgt **Just Works**: iOS zeigt nur einen Bestätigungsdialog. Bonding mit LTK und IRK in beide Richtungen. Die Pumpe fordert das MITM-Flag, bekommt es aber nicht erfüllt. Das deckt sich mit OpenMinimed.
4. **MTU:** Die Pumpe fragt 184 an, iOS antwortet mit 184. **Kein Abbruch** (anders als bei BlueZ ohne Patch). Unter iOS ist kein MTU-Workaround nötig.
5. **✅ iOS-Kernfrage beantwortet: Das iPhone macht auf derselben Verbindung GATT-Discovery als Client** (Read By Group Type, Find Information, Read By Type, Read und Write Requests vom iPhone an die Pumpe). Gleichzeitig bedient es die Pumpe als GATT-Server. Bidirektionales GATT über eine eingehende Verbindung funktioniert also mit öffentlicher CoreBluetooth-API.
6. **Die Pumpe trennt nach etwa 67 s** (20:50:39, Reason 0x13 „Remote User Terminated“). Die App sendet danach sofort Advertising mit `0xFE81` und 30 ms. → Das deutet auf ein **periodisches Verbindungsmodell** hin (Pumpe verbindet, synct, trennt, etwa alle 5 min). Prüfen wir in Mitschnitt 2.

### Offene Fragen für Mitschnitt 2
- Bleibt das Advertising mit `FE81` und 30 ms erhalten, wenn die App im Hintergrund ist bzw. das iPhone gesperrt ist?
- Wie oft verbindet sich die Pumpe? Wie lange dauert eine Sitzung?
