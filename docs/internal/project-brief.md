# Projekt: open780 – lokaler, lesender Zugriff auf die MiniMed 780G

Du bist mein Engineering-Partner für dieses Projekt und arbeitest auf meinem Mac. Ziel ist eine quelloffene iOS- und Android-App, die Daten einer Medtronic MiniMed 780G **ausschließlich lesend** per Bluetooth LE ausliest und lokal über eine REST-API bereitstellt, ohne Abhängigkeit von der CareLink-Cloud. Der Projektname ist ein Platzhalter. Schlag gerne einen besseren vor.

## Kontext
- Ich bin Entwickler mit Erfahrung in Netzwerk-/IoT-Troubleshooting und betreibe ein eigenes Nightscout/Pebble-CGM-Projekt (supercgm). Die Daten sollen später auch dort einfließen.
- Ich habe eine **ausrangierte 780G als Testgerät**. Ich kann sie koppeln, in den Kopplungsmodus versetzen und zurücksetzen. Physische Schritte an der Pumpe mache ich. Sag mir jeweils genau, was ich wann tun soll.
- Es ist möglich, dass die Kopplung einen Token oder eine Freischaltung über Medtronic-Server braucht. Das ist eine zentrale offene Frage.
- Rechtsrahmen: Reverse Engineering zur Interoperabilität (EU, §69e UrhG) und Datenzugangsrecht nach EU Data Act für mein eigenes Gerät.

## Harte Regeln (nicht verhandelbar)
1. **Nur lesen.** Implementiere, teste oder sende niemals Befehle, die Therapie, Einstellungen oder Zustand der Pumpe verändern (Bolus, Basal, Temp-Basal, Suspend, Einstellungen, Zeit, Alarme quittieren usw.). Der Protokoll-Client bekommt eine **Allowlist** erlaubter Opcodes/Nachrichtentypen. Alles andere wird hart blockiert und geloggt. Wenn unklar ist, ob eine Nachricht schreibend wirkt, gilt sie als verboten. Frag dann mich.
2. **Nur das Testgerät.** Experimente laufen ausschließlich gegen die Test-Pumpe. Ich trage ihre Seriennummer in `.env` ein (`TEST_PUMP_SERIAL`). Code verweigert Verbindungen zu anderen Seriennummern, solange `DEV_MODE` aktiv ist.
3. **Kein proprietäres Material im Repo.** Dekompilierter Code, APK/IPA-Dateien, extrahierte Schlüssel, Zertifikate und Medtronic-Assets bleiben **lokal in einem gitignorierten Ordner** (`_vendor/`). Ins Repo kommen nur eigene Notizen, eigene Protokollbeschreibungen und eigener Code (Clean-Room-Ansatz, damit das Projekt später veröffentlicht werden kann).
4. **Secrets** (Tokens, Pairing-Keys, CareLink-Zugang, Mitschnitte mit personenbezogenen Daten) gehören nie in Git. Nutze `.env`, den macOS-Schlüsselbund oder gitignorierte Ordner. Prüf vor jedem Commit mit einem Secret-Scan (z. B. `gitleaks`).
5. **Medtronic-Server:** Den Datenverkehr meiner eigenen App-Sitzungen mitzuschneiden und zu analysieren ist in Ordnung. Keine Last-, Fuzzing- oder sonstigen Angriffe auf Medtronic-Infrastruktur, keine fremden Accounts. Frag mich, bevor du selbst Requests an Medtronic-Server schickst.
6. Halt vor irreversiblen oder riskanten Schritten an und frag mich (z. B. Firmware-Themen, Werksreset, Root/Jailbreak).

## Arbeitsweise
- Arbeite in Phasen. Am Ende jeder Phase: kurze Zusammenfassung, Entscheidungen, offene Fragen. Dann warte auf mein Go.
- Führ eine Aufgabenliste und halte sie aktuell.
- **Wissen gehört ins Repo:** Erkenntnisse sofort in `docs/` festhalten, nicht nur im Chat. Entscheidungen als kurze ADRs in `docs/internal/decisions/`. Ein laufendes Laborbuch in `docs/internal/lab-notebook.md` (Datum, was getestet, Ergebnis, Mitschnitt-Datei).
- Kleine, sinnvolle Commits mit Conventional Commits. Push nach jedem abgeschlossenen Schritt.
- Lege eine `CLAUDE.md` im Repo an, die Ziel, harte Regeln, Repo-Struktur und den aktuellen Stand enthält. Halte sie aktuell, damit spätere Sessions nahtlos weitermachen können.

## Phase 0 – Umgebung und Repo
1. Prüfe und installiere fehlende Tools per Homebrew (vorher Liste zeigen): `git`, `gh`, `python@3.12` + `uv`, `jadx`, `apktool`, `adb` (android-platform-tools), `wireshark`, `mitmproxy`, `frida-tools`, `gitleaks`, `bleak` (Python, BLE vom Mac aus). Prüf, ob Xcode samt Command Line Tools installiert ist. Weise mich auf Apples „Additional Tools for Xcode“ (PacketLogger) und das iOS-Bluetooth-Logging-Profil hin.
2. Leg ein **privates** GitHub-Repo an (`gh repo create --private`). Vorgeschlagene Struktur:
   ```
   docs/            # Protokoll, Recherche, ADRs, Laborbuch
   research/        # eigene Analyse-Skripte und Notizen (kein Vendor-Code)
   captures/        # gitignored: Roh-Mitschnitte (btsnoop, pcap, mitm)
   _vendor/         # gitignored: APK/IPA, Dekompilate, extrahiertes Material
   proto/           # Python-Referenzimplementierung (bleak), Replay-Tools
   core/            # gemeinsame Protokoll-Bibliothek für die Apps
   apps/ios/        # SwiftUI-App
   apps/android/    # Kotlin-App
   ```
3. `.gitignore`, `.env.example`, Pre-Commit-Hook mit gitleaks, README mit Disclaimer („nicht für Therapieentscheidungen, keine Medizinprodukt-Zulassung“). Lizenz zunächst offen lassen, aber Optionen in einem ADR dokumentieren.

## Phase 1 – Recherche: Was gibt es schon, was ist wiederverwendbar?
Recherchiere gründlich im Web und auf GitHub. Lies Code und Issues, nicht nur READMEs. Ergebnis ist `docs/internal/landscape.md` mit einer Matrix aus Projekt, Gerät/Protokoll, Status, Lizenz, Wiederverwendbarkeit und relevanten Erkenntnissen. Mindestens:
- `pazaan/600SeriesAndroidUploader`, besonders Issue #296 (770G/780G-Protokoll, USB-„Blue Adapter“ 1003910) und alle Forks/Folgeprojekte der Beteiligten (z. B. ondrej1024)
- `nightscout/minimed-connect-to-nightscout`, CareLink-Follower in xDrip+ und Nightscout-Connect
- xDrip+, AndroidAPS, Loop/Trio, OpenAPS: Medtronic-Support, BLE-Abstraktionen, Treiber-Architektur
- Ältere Medtronic-Protokollarbeit (decoding-carelink, RileyLink-Ökosystem) als Hintergrund
- Gezielte Suchen nach: 780G/770G BLE, MiniMed Mobile App Reverse Engineering, Medtronic BLE Pairing/Key-Exchange, GATT-UUIDs, Sicherheitsforschung/CVEs zu 770G/780G, Konferenzvorträge
- **Kernfrage:** Gibt es bereits eine entschlüsselte bzw. verstandene BLE-Kommunikation (insbesondere auf Android), auf der wir aufbauen können? Wenn ja: Lizenz, Vollständigkeit, wie aktuell (Firmware-Versionen)?
- Gibt es Communities (Discord, Gitter, Facebook-Gruppen, Foren), wo daran gearbeitet wird? Halte Kontaktpunkte fest, damit wir uns anschließen statt parallel zu bauen.

Danach gibst du eine Empfehlung: anschließen, forken oder neu aufbauen.

## Phase 2 – Statische Analyse der MiniMed-Mobile-App
- **Android zuerst:** Ich installiere die offizielle App auf einem Test-Android-Gerät. Zieh die APK per `adb` vom Gerät (inkl. Split-APKs) nach `_vendor/`. Analysiere mit jadx/apktool: BLE-GATT-Services und -Characteristics, Pairing-Flow, Kryptografie (Key-Exchange, Session-Keys, Algorithmen), Nachrichtenformate/Opcodes, Cloud-Endpunkte im Pairing-Prozess, Zertifikats-Pinning, native Libraries (`.so`, ggf. mit Ghidra).
- **iOS:** IPAs aus dem App Store sind FairPlay-verschlüsselt. Bewerte nur, ob eine iOS-Analyse zusätzlichen Erkenntnisgewinn bringt. Kein Jailbreak ohne Rücksprache.
- Dokumentiere alles in eigenen Worten in `docs/internal/`. Keine Code-Kopien aus dem Dekompilat ins Repo.

## Phase 3 – Dynamische Analyse: Kopplung mitschneiden
Plane mit mir eine Pairing-Session mit der Test-Pumpe und schneide gleichzeitig mit:
- **BLE:** Android-HCI-Snoop-Log (Entwickleroptionen) bzw. iOS PacketLogger. Optional ein nRF52-Sniffer, falls nötig (sag mir, ob sich die Anschaffung lohnt).
- **HTTPS:** mitmproxy auf dem Mac als Proxy für das Testgerät. Bei Zertifikats-Pinning: Frida-Bypass auf dem eigenen Testgerät, nur nach Rücksprache.
- Ziel: Klären, ob und wie die Kopplung Server-Interaktion braucht (Token, Zertifikat, Gerätefreischaltung), was davon einmalig und was dauerhaft ist, und ob ein lokales Pairing ohne Cloud realistisch ist.
- Mitschnitte nach `captures/` mit Zeitstempel. Annotierte Auswertung ins Laborbuch.

## Phase 4 – Referenzimplementierung auf dem Mac
- Python-Prototyp mit `bleak` in `proto/`: Scannen, Verbinden, Pairing/Session aufbauen, **lesende** Abfragen (Sensorwert, Trend, IOB, Reservoir, Batterie, Status, Historie), alles mit Opcode-Allowlist.
- Replay- und Parser-Tools für Mitschnitte, Unit-Tests gegen echte (anonymisierte) Frames.
- Eine maschinenlesbare Protokollbeschreibung, aus der sich Parser für Swift/Kotlin ableiten lassen.

## Phase 5 – Apps und lokale REST-API
- Erstelle ein ADR zur Architektur: gemeinsamer Core (z. B. Kotlin Multiplatform oder Rust mit Bindings) vs. zwei native Implementierungen.
- **iOS:** SwiftUI + CoreBluetooth, bauen und testen mit Xcode über `xcodebuild`. Wichtig: Der iOS-Simulator hat **kein Bluetooth**. Baue deshalb eine Transport-Abstraktion mit einem Mock/Replay-Transport aus echten Mitschnitten, damit UI und Parser im Simulator laufen. Echte BLE-Tests mache ich auf meinem iPhone (sag mir, was dafür nötig ist: Signing, Background-Modes).
- **Android:** Kotlin, gleiches Prinzip, Emulator mit Replay-Transport.
- **REST-API:** lokaler HTTP-Server in der App (nur LAN/localhost, mit Token-Auth), optional Nightscout-kompatible Endpunkte bzw. Upload zu meinem eigenen Nightscout. Hintergrundbetrieb und Akkuverbrauch berücksichtigen.
- Die App darf die offizielle MiniMed-App nicht unbemerkt verdrängen. Kläre, wie viele BLE-Verbindungen/Pairings die Pumpe erlaubt, und dokumentiere die Konsequenzen.

## Phase 6 – Vorbereitung Open Source (später)
Clean-Room-Prüfung des Repos, Lizenzentscheidung, Disclaimer, Security-Policy, Distributionswege (TestFlight/Selbst-Build, F-Droid/GitHub Releases).

---

**Starte jetzt mit Phase 0.** Zeig mir zuerst die Tool-Liste und den geplanten Repo-Namen, bevor du installierst oder das Repo anlegst.
