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

## 2026-10-14 · Mitschnitt 2: Reconnect-Verhalten der offiziellen App (iOS)
- **Mitschnitt:** `captures/2026-10-14_2047_mmm-ios-reconnect-tests_pump2.pklg` (20:47–21:37, enthält Mitschnitt 1)
- **Simons Notizen:** A: Werte im 5-Minuten-Takt (20:47, 20:52, …), App im Hintergrund, iPhone gesperrt · B: ab 21:14 Pumpe außer Reichweite · C: 21:23 Bluetooth aus (vorher kurz an/aus), ca. 21:25 an, ca. 21:27 wieder verbunden · D: 21:27 App beendet, ca. 21:33 geöffnet, 21:37 wieder verbunden
- Pumpen-Verbindungen sind über die Medtronic-OUI `00:23:f7` erkennbar bzw. über GATT-Verkehr auf den Medtronic-UUIDs. Andere Handles gehören zu Uhr, AirPods usw.
- ⚠️ PacketLogger hat **nicht alle HCI-Events** aufgezeichnet. Für die Pumpenverbindung `0x0402` fehlen sowohl Connection Complete (ca. 20:51:23) als auch Disconnect (spätestens bei Test C). Aussagen dazu stützen sich auf den ATT-Verkehr.

### Ergebnisse
1. **Dauerhafte Verbindung statt periodischer Verbindungen.** Nach der Kopplung trennt die Pumpe einmal (20:50:39) und verbindet sich nach 44 s erneut (20:51:23, auf `FE81`-Advertising mit 30 ms). Danach **bleibt die Verbindung bestehen**: History-Download 20:51–20:53 (viele Notifications auf *IDD History Data* `…0108`), anschließend kleiner Verkehr jede Minute und Bursts im 5-Minuten-Takt (Sensorwerte). Das gilt auch **mit gesperrtem iPhone und App im Hintergrund** (Test A).
2. **Die App sendet nach dem Verbindungsaufbau kein eigenes Advertising mehr.** Von 20:51:23 bis zum erneuten Öffnen um 21:34 enthält das Advertising-Set 0 nur Apples eigene Nearby- bzw. Continuity-Daten (`0x10…`, `0x0c…`), connectable, 30–270 ms, mit der RPA des iPhones.
3. **🔑 Der Reconnect braucht kein `FE81`.** In Test C verbindet sich die Pumpe um 21:26:29 neu (Encryption per LTK aus dem Bond, MTU 184). Zu diesem Zeitpunkt sendet das iPhone **nur Apple-Advertising ohne Medtronic-UUID**. → Die Pumpe löst die RPA des iPhones über den beim Bonding getauschten **IRK** auf und verbindet sich mit *jedem* connectable Advertising des gebondeten Geräts. Damit ist das **Risiko „Hintergrund-Advertising unter iOS“ weitgehend entschärft**: iOS sendet ohnehin dauerhaft connectable Advertising. `FE81` beschleunigt den Reconnect nur.
4. **Test D (App beendet):** Beim Beenden kappt iOS die Verbindung (21:27:44, Reason 0x16 *Local Host Terminated*). Die Pumpe verbindet sich trotzdem mit dem iPhone (21:29:09, 21:29:39, 21:29:55), weil sie die Apple-Adverts per IRK erkennt. Jede Verbindung bricht nach ca. 7 s ab (Reason 0x08 *Connection Timeout*), weil keine App den GATT-Server bzw. SAKE bedient. Danach zieht sich die Pumpe zurück (Backoff). Nach dem Öffnen (FE81 mit 30 ms ab 21:34:39) wieder verbunden um 21:36:34. **Folge für uns:** Eine beendete App bekommt keine Daten. Das ist bei iOS erwartbar, denn State Restoration greift nach Force-Quit nicht.
5. **Test B (außer Reichweite):** Wegen der fehlenden HCI-Events nicht eindeutig. Auf `0x0402` gibt es bis 21:13 regelmäßigen Verkehr, dann nur wenig (21:17), dann einen Burst um 21:21 (vermutlich Nachladen nach der Rückkehr). → Simon fragen, wann die Pumpe zurück war. Ggf. wiederholen.
6. **MTU:** bei der Erstverbindung und nach Bluetooth an/aus jeweils 184 (von der Pumpe angefragt).

### Folgen für die iOS-App
- Background Modes `bluetooth-peripheral` und `bluetooth-central` plus State Restoration reichen voraussichtlich aus. Die App muss im Hintergrund nur **erreichbar bleiben**, nicht dauerhaft `FE81` senden.
- Nach dem Start der App sollte sie kurz `FE81` mit kurzem Intervall senden (macht MiniMed Mobile genauso, nur im Vordergrund nötig).
- Der GATT-Server (SAKE-Port und DIS) muss immer registriert sein, sobald die App läuft, sonst bricht die Pumpe nach ca. 7 s ab.

## 2026-10-14 – Was die offizielle App auf der Dauerverbindung schreibt (Mitschnitt 2)

Auswertung der Schreibzugriffe des iPhones auf die Pumpe (Link `0x0402`), um unsere Allowlist an der Praxis zu prüfen:

- **CGM RACP:** 9 × `01 06` (Report Stored Records, Last Record), Antwort `06 00 01 01` (Erfolg). Identisch mit OpenMinimed. → In unserer Allowlist.
- **IDD Status Reader CP:** 93 verschlüsselte Schreibzugriffe (5 und 11 Byte, also 2 bzw. 8 Byte Klartext). Die 2-Byte-Variante passt zu den Get-Opcodes ohne Parameter. Die 8-Byte-Variante ist ein Opcode mit Parametern, noch nicht identifiziert (vermutlich aktive Boli). → Nicht in der Allowlist.
- **IDD RACP** (unverschlüsselt): `33 69 0f` (Report Stored Records, Last) und `33 5a 0f <u32> <u32>` (Records im Sequenzbereich). So lädt die App die Historie nach. Kein Delete (`0x3c`) beobachtet. → Für die spätere History-Funktion; derzeit blockiert.
- **CGM Specific Ops CP:** 3 verschlüsselte Zugriffe (Längen passend zu `0x90` Sensordetails und `0x81` Kalibrierkontext). → Blockiert, nicht nötig.
- **Unbekannt:** 5 × 18 Byte auf Handle `0x0081` (`00 2c 00 00 00 06 07 00 01 80 00 02 28 00 03 c8 00 05`, erstes Byte zählt hoch) und 4 × Write Command auf `0x0099` (`28 00 02 00 30 ff 03` usw.). Wahrscheinlich History & Trace bzw. Streaming. Zuordnung zu UUIDs fehlt, weil iOS die GATT-Discovery gecacht hat. → Blockiert.

Folge: Unsere Allowlist ist eine echte Teilmenge dessen, was die offizielle App tut. Neue Befehle nehmen wir nur nach Rückfrage auf.

## 2026-10-14 – Erster Kopplungsversuch: „Gerät nicht kompatibel“

- **Beobachtung (Simon):** Die Pumpe findet „Mobile …“, die Kopplungsanfrage wird auf dem iPhone bestätigt, danach meldet die Pumpe „Gerät nicht kompatibel“.
- **Analyse Mitschnitt 1:** Nach der BLE-Kopplung sucht die Pumpe auf dem iPhone den SAKE-Service (FE82) und den DIS 0x0900. Sie liest **alle** DIS-Werte, bevor sie die SAKE-Notifications abonniert. Die offizielle iOS-App liefert:

  | Merkmal | Wert |
  |---|---|
  | 2A29 Hersteller | `Apple` |
  | 2A24 Modell | Hardware-Kennung, z. B. `iPhone19,2` |
  | 2A25 Seriennummer | `Mobile <Name aus dem Advertising>` |
  | 2A27 Hardware | `iPhone` |
  | 2A26 Firmware | `iOS` |
  | 2A28 Software | App-Version `3.3.0(80)` |
  | 2A23 System ID | 8 × `00` |
  | 2A50 PnP ID | 7 × `00` |
  | 2A2A Zertifikatsliste | leer |

  Die SAKE-Port-Characteristic hat dort die Properties `0x98` (Write, Notify, Extended Properties) mit Deskriptor 0x2900.
- **Unsere erste Version wich ab:** eigene Werte, Seriennummer ohne „Mobile “, Software `0.1.0`, **2A2A fehlte**.
- **Hypothesen:** (a) fehlende 2A2A, (b) Software-Version unter einer Mindestversion, (c) Seriennummer muss zum angezeigten Namen passen.
- **Änderung:** Die DIS-Werte sind jetzt aus Gründen der Interoperabilität identisch zur offiziellen App (Software-Version als Konstante `PumpLink.compatSoftwareRevision`). Jede Leseanfrage der Pumpe wird protokolliert. Die GATT-Tabelle ist versioniert, damit wiederhergestellte alte Services ersetzt werden.
- **Offen:** Die Extended Properties der SAKE-Characteristic kann CoreBluetooth vermutlich nicht nachbilden. Die Android- und Linux-Varianten kommen ohne aus.

## 2026-10-14 – Erster erfolgreicher Betrieb und Hintergrund-Problem

- **Kopplung mit openMinipump klappt** (nach der DIS-Anpassung). Gelesen wurden SG, IOB, Reservoir, Pumpenbatterie, SmartGuard-Status, TIR und Sensorstart. Die Werte sind plausibel und stimmen mit der Pumpe überein.
- **0x0202 „Time Of Sensor Expiration“** liefert 8 Nullbytes + CRC, nicht das dokumentierte u16. Der Sensorablauf wird deshalb aus Sensorstart (0x2AAA) + Session Run Time (0x2AAB, Stunden) berechnet.
- **Hintergrund:** Automatische Aktualisierung blieb aus, manuell ging es. Im Mitschnitt 2 beginnt jeder 5-Minuten-Zyklus mit einer Notification auf GST Battery Level (0x0400) und einer Indication auf IDD Status Changed (0x0101); die offizielle App fragt danach SRCP, Sensorstart und CGM-RACP ab.
- **Maßnahmen:** Beide Signale (und spontane CGM-Messungen) lösen die Abfrage aus, auch wenn die Entschlüsselung scheitert. Hängende Abfragen werden über die Zeit erkannt, da Timer in suspendierten Apps nicht laufen. Die SAKE-Sitzung (Schlüssel, Nonce, Zähler) wird gespeichert und nach einem Neustart der App durch iOS fortgesetzt. Das Protokoll wird zusätzlich in `Application Support/openminipump.log` geschrieben.

## 2026-10-14 – Sitzung, Selbstheilung, Historie

- **Sitzung über App-Neustart:** Nach einem Update setzt die App die gespeicherte SAKE-Sitzung fort; die Pumpe bleibt verbunden, Entschlüsselung läuft weiter (verifiziert).
- **Ohne Sitzung:** Das Neu-Registrieren der eigenen GATT-Dienste lässt die Pumpe die Verbindung nach ~7 s per Timeout trennen und ~25 s später mit neuem Handshake zurückkommen (verifiziert). Ändert nichts an der Pumpe.
- **CGM RACP „≥ Zeit-Offset“** (`01 03 01 <u16>`) beantwortet die 780G mit `06 00 01 04` (Operator not supported). Die Historie muss über die IDD-History (RACP `33 5a 0f <Seq-Bereich>`, wie die offizielle App) geholt werden → nächster Ausbauschritt, braucht den History-Parser.
- **GST Battery Level (0x0400)** ist auf der 780G nur per Notification verfügbar, Lesen liefert „Reading is not permitted“.
