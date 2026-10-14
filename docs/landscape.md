# Landscape: Was gibt es schon? (Stand 2026-10-14)

Recherche für Phase 1. Kurzfassung vorab: **Die BLE-Kommunikation der 700er-Serie (680G/770G/780G) ist geknackt und öffentlich dokumentiert.** Das hat das Projekt **OpenMinimed** geleistet (GPL-3.0). Pairing und Datenabruf funktionieren **komplett lokal, ohne Medtronic-Server**. Eine **iOS-Implementierung gibt es bisher nicht.**

## 1. Matrix

| Projekt | Gerät / Weg | Status (letzter Push) | Lizenz | Wiederverwendbarkeit für uns | Erkenntnisse |
|---|---|---|---|---|---|
| **[OpenMinimed/Documentation](https://github.com/OpenMinimed/Documentation)** | 700er-Serie, BLE | aktiv (2026-09) | keine Lizenzdatei | ★★★ Hauptquelle für das Protokollverständnis | GATT-Services von Pumpe und App, Advertising (FE82 Pairing / FE81 Reconnect), SAKE-Handshake, Key-DB-Format, Opcodes für IOB, TIR, SmartGuard-Status, History-Events |
| **[OpenMinimed/PythonSake](https://github.com/OpenMinimed/PythonSake)** | SAKE-Krypto | aktiv (2026-09) | GPL-3.0 | ★★★ Referenz für die Swift-Portierung | Vollständiger Client und Server, SeqCrypt (AES-CTR + gekürzter CMAC) |
| **[OpenMinimed/PythonPumpConnector](https://github.com/OpenMinimed/PythonPumpConnector)** | 780G ↔ Linux-PC | aktiv (2026-10) | GPL-3.0 | ★★★ Referenzimplementierung und Ground Truth | Pairing und Reconnect laufen ohne Medtronic-Software. Liest SG, Trend, IOB, Reservoir, Batterie, SmartGuard, TIR und History (nur die letzten ~4–5 Tage). **Nur Linux/BlueZ** (gepatcht: MTU 23 bei der Discovery, `Privacy=device`). |
| [OpenMinimed/JavaSake](https://github.com/OpenMinimed/JavaSake) | SAKE-Krypto (JVM) | 2026-07 | GPL-3.0 | ★★ Vorlage für Android, auf Maven Central | Parität zu PythonSake per Testvektoren aus einem echten 780G-Trace |
| [OpenMinimed/JavaPumpConnector](https://github.com/OpenMinimed/JavaPumpConnector) | Android | 2026-06 | GPL-3.0 | ★ | nur Verbindung und Handshake, keine Daten |
| **[OpenMinimed/PebbleOS](https://github.com/OpenMinimed/PebbleOS)** (Fork) | 780G → Pebble-Uhr direkt | sehr aktiv (2026-10) | Apache-2.0 (Fork) | ★★ Praxiswissen zur Verbindung | Uhr koppelt **direkt** mit der Pumpe, ohne Telefon. `CONNECTIVITY.md` enthält viel Wissen zu Bonds, Advertising, FE81/FE82-Zustand und Reconnect-Backoff der Pumpe (1–15 min). Spricht das [Pebble Glucose Protocol](https://github.com/mortenfyhn/pebble-glucose-protocol) (0BSD). **Relevant für supercgm.** |
| OpenMinimed/SakeLibraryRE, NativeSakeTests, FridaScripts, JadxProjects | RE-Werkzeuge | 2026 | – | ☆ nicht übernehmen (Vendor-nah) | belegt, wie die Key-DBs gewonnen wurden |
| **[lumose-health/GlycemicGPT](https://github.com/lumose-health/GlycemicGPT)** + [android-unofficial](https://github.com/lumose-health/android-unofficial) | 680G/770G/780G via BLE (Android) + CareLink | sehr aktiv | GPL-3.0 | ★★ Android-Vorlage, Plugin-Architektur | Erster App-Treiber, read-only, nutzt JavaSake. Koppelt als „Mobile 000001“. IOB wurde gegen eine echte 780G geprüft, SG nur auf der 780G bestätigt, SmartGuard-Mikroboli nicht sauber zugeordnet. **Kein iOS-BLE-Treiber** (die iOS-App ist nur ein TestFlight-Build ohne Pumpenanbindung). Issue [#708](https://github.com/lumose-health/GlycemicGPT/issues/708). |
| [pazaan/600SeriesAndroidUploader](https://github.com/pazaan/600SeriesAndroidUploader) | 640G/670G über USB/Contour Next Link | **archiviert** (2022) | MIT | ☆ historisch | [Issue #296](https://github.com/pazaan/600SeriesAndroidUploader/issues/296) (2020): ondrej1024 fragt nach dem 780G-Protokoll. Ergebnis damals: niemand arbeitet daran. Idee mit dem Blue Adapter 1003910 (USB), nicht weiterverfolgt. |
| [ondrej1024/m5-minimed-monitor](https://github.com/ondrej1024/m5-minimed-monitor), [carelink-python-client](https://github.com/ondrej1024/carelink-python-client) | 780G via CareLink-Cloud | aktiv | GPL-3.0 / AGPL-3.0 | ★ als Fallback und Vergleich | Cloud-Follower, kein BLE |
| [nightscout/minimed-connect-to-nightscout](https://github.com/nightscout/minimed-connect-to-nightscout) | CareLink-Cloud → Nightscout | 2026-03 | MIT | ★ Mapping auf Nightscout | Cloud-Scraper. Nützlich für das Datenmapping nach Nightscout (Felder, Trendpfeile). |
| [nightscout/nightscout-connect](https://github.com/nightscout/nightscout-connect) | diverse Clouds, u. a. CareLink | aktiv | AGPL-3.0 | ☆ | Cloud |
| [xDrip+](https://github.com/NightscoutFoundation/xDrip) | CareLink-Follower | aktiv | GPL-3.0 | ☆ | [Diskussion #2438](https://github.com/NightscoutFoundation/xDrip/discussions/2438) von 2023: „not until we break the encryption“. Das ist inzwischen überholt. |
| [AndroidAPS](https://github.com/nightscout/AndroidAPS) | nur alte Medtronic-Pumpen via RileyLink | aktiv | AGPL-3.0 | ☆ | Die Doku sagt ausdrücklich: keine „G“-Modelle, also auch nicht 770G/780G |
| [Trio](https://github.com/nightscout/Trio) / [MinimedKit](https://github.com/LoopKit/MinimedKit) / [rileylink_ios](https://github.com/ps2/rileylink_ios) | alte Medtronic-Pumpen via 916-MHz-RF | aktiv | MIT | ☆ Architektur-Inspiration für iOS (PumpManager-Muster) | kein 700er-BLE |
| openaps/decoding-carelink | 5xx/7xx-RF-Protokoll | historisch | MIT | ☆ | anderes Protokoll |

## 2. Kernfragen beantwortet

### Gibt es eine verstandene BLE-Kommunikation?
**Ja.** OpenMinimed dokumentiert:
- **Rollen sind vertauscht:** Die Pumpe ist BLE-**Central**, das Telefon ist **Peripheral** und gleichzeitig SAKE-**Server**. Das Telefon sendet Advertising, die Pumpe verbindet sich.
- **Erstkopplung:** Advertising mit dem 16-Bit-Service `0xFE82` und dem Namen `"Mobile "` plus 0–7 ASCII-Zeichen. Der Nutzer wählt das Gerät im Pumpenmenü „Neues Gerät koppeln“. BLE-Pairing läuft als *Just Works*, es gibt keine LE Secure Connections.
- **Reconnect:** Advertising mit `0xFE81`, zuverlässig nur bei einem Intervall von ≤ 150 ms und **nur mit Resolvable Private Address**. Die Pumpe scannt mit Backoff, nach längeren Ausfällen dauert es bis zu ~15 min.
- **SAKE:** 6-Nachrichten-Handshake auf dem SAKE-Port (`0000fe82-…-009132591325`). Danach werden ausgewählte Characteristics per AES-CTR verschlüsselt, mit 2 Byte CMAC auf dem Draht. Die Schlüssel stehen in **statischen Key-Datenbanken pro Gerätetyp-Paar**, die bei allen Pumpen identisch sind.
- **Datenservices:** angelehnt an Standard-Bluetooth-SIG-Profile mit Medtronic-UUIDs: IDS (Insulin Delivery) und CGMS, dazu eigene Services (History & Trace, NOS, SSE, Certificate Management, Firmware Update).

### Braucht die Kopplung Medtronic-Server oder einen Token?
**Nein**, zumindest nicht für die Grundfunktion. PythonPumpConnector und die Pebble-Firmware koppeln ohne Internet und ohne Medtronic-Software. Damit ist die zentrale offene Frage aus dem Brief weitgehend beantwortet. Offen bleibt, wofür der *Certificate Management Service* gebraucht wird, z. B. für das CareLink-Upload-Zertifikat. Das klären wir beim Mitschnitt in Phase 3.

### Wie aktuell, welche Firmware?
Getestet ist vor allem die **780G**. Die Key-DB „Mobile Application ↔ Insulin Pump“ gilt für die ganze 700er-Serie. Eine Firmware-Matrix gibt es nicht. → **Wir halten die Firmware-Version unserer Testpumpe im Laborbuch fest.**

### Wie viele Verbindungen erlaubt die Pumpe?
**Ein „Mobile“-Peer gleichzeitig.** Unsere App würde MiniMed Mobile auf dem Telefon ersetzen, nicht ergänzen. Ein theoretischer Ausweg wäre die Kopplung als *CareLink Upload Application* (Gerätetyp 5), die einen eigenen Slot hätte. Dafür fehlt aber der Key-DB-Dump ([PythonPumpConnector #4](https://github.com/OpenMinimed/PythonPumpConnector/issues/4)). Für dich mit der ausrangierten Testpumpe ist das egal, für spätere Nutzer ist es ein wichtiger Hinweis.

## 3. iOS-Machbarkeit (unser Alleinstellungsmerkmal und das größte Risiko)

Das Rollenmodell hat harte Folgen für CoreBluetooth:

| # | Anforderung | iOS-Lage | Risiko |
|---|---|---|---|
| 1 | Advertising `0xFE82` + Name „Mobile …“ | `CBPeripheralManager` kann Service-UUID und LocalName senden, **aber nur im Vordergrund**. Für die Erstkopplung reicht das. | niedrig |
| 2 | Eigener GATT-Server (SAKE-Port, DIS unter `0x0900`) | möglich. GAP/GATT (`0x1800/0x1801`) verwaltet iOS selbst, deshalb ist die GAP-Device-Name-Characteristic der iPhone-Name. Ob die Pumpe das akzeptiert, ist offen. | mittel |
| 3 | **GATT-Client auf derselben Verbindung** (Pumpen-Services IDS/CGMS lesen) | Die Pumpe ist Central. Wir müssen ihre Services über die Verbindung lesen, die sie selbst aufgebaut hat. Weg über `CBCentralManager.retrieveConnectedPeripherals(withServices:)`. | **hoch, muss früh verifiziert werden** |
| 4 | MTU 23 während der Discovery | Unter Linux muss BlueZ gepatcht werden. iOS handelt die MTU selbst aus, wir haben keinen Einfluss. | **hoch** |
| 5 | **Reconnect im Hintergrund** (`0xFE81`, ≤ 150 ms, RPA) | iOS verwendet RPA, das passt. Im Hintergrund verschiebt iOS Service-UUIDs aber in den proprietären „Overflow“-Bereich und sendet seltener Advertising. **Die Pumpe sieht `0xFE81` dann vermutlich nicht.** | **sehr hoch** |
| 6 | Dauerbetrieb im Hintergrund | `bluetooth-peripheral` und `bluetooth-central` als Background Modes, State Restoration | mittel |

**Existenzbeweis:** Die offizielle **MiniMed Mobile gibt es für iOS**, und sie läuft mit öffentlichen CoreBluetooth-APIs. Punkte 2–6 sind also grundsätzlich lösbar. *Wie* Medtronic es macht, insbesondere den Reconnect im Hintergrund, sehen wir am besten per **PacketLogger-Mitschnitt der offiziellen iOS-App** (Phase 3). Das ist erlaubt und braucht keinen Jailbreak.

## 4. Communities und Kontaktpunkte
- **OpenMinimed-Discord:** https://discord.gg/tb4egy8VYh (Kernteam: palmarci/Pál Marci, drfubar, Morten Fyhn Amundsen, Stenium, planiitis)
- **GlycemicGPT-Discord:** https://discord.gg/QbyhCQKDBs (jlengelbrecht, Android-Treiber)
- PebbleOS-Fork-Issues (mortenfyhn): Pebble ↔ 780G direkt
- ondrej1024 (ursprünglicher Initiator von #296, m5-minimed-monitor)

## 5. Empfehlung: **anschließen und den iOS-Teil neu bauen**

- **Protokoll und Krypto nicht neu erfinden.** OpenMinimed ist die Upstream-Quelle. Wir stellen uns im Discord vor und melden, dass wir iOS angehen. Das tut sonst niemand.
- **Neu bauen:** eine **Swift-Portierung von PythonSake** (eigenständiges Paket, z. B. `SwiftSake`, GPL-3.0, wird upstream angeboten) plus iOS-Transport und App. Das ist kein Fork, weil es keinen iOS-Code gibt, von dem wir forken könnten.
- **Android später** auf Basis von JavaSake bzw. mit Blick auf den GlycemicGPT-Treiber, damit wir keine Parallelarbeit machen.

### Folgen für den Brief (Vorschlag, braucht dein Go)
1. **Lizenz → GPL-3.0** wird praktisch zwingend, sobald wir PythonSake portieren (ADR 0002 wird dann aktualisiert). Für iOS bedeutet das Selbst-Build bzw. TestFlight, kein App Store. GlycemicGPT macht es genauso.
2. **Clean-Room-Regel und Key-DB:** Die SAKE-Key-DB ist aus Firmware bzw. App extrahiert. Sie ist bei OpenMinimed öffentlich, nach Regel 3 aber trotzdem „extrahiertes Material“. Vorschlag: **nicht in unser Repo**. Die DB wird zur Build- oder Laufzeit aus `_vendor/` bzw. aus einer lokalen Konfiguration geladen. Ob das bei Veröffentlichung praktikabel ist, entscheiden wir in Phase 6.
3. **Phase 2 (APK-Analyse) wird stark verkürzt.** Das Protokoll ist bekannt, nur noch gezielte Fragen bleiben (z. B. Certificate Management). **Phase 3 bekommt einen anderen Schwerpunkt:** PacketLogger-Mitschnitt der *offiziellen iOS-App*, um iOS-Fragen 3–5 zu klären.
4. **`bleak` scheidet für den Prototyp aus**, weil es nur die Central-Rolle kann. Vorschlag für die Ground Truth: **PythonPumpConnector unverändert auf einem Raspberry Pi** (Linux/BlueZ) gegen die Testpumpe laufen lassen. Für das iOS-Risiko: **direkt ein minimaler Swift-Spike** (`CBPeripheralManager` + `retrieveConnectedPeripherals`), zuerst als macOS-CLI auf dem Mac (gleiche API), dann auf dem iPhone.
