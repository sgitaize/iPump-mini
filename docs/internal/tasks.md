# Aufgabenliste

## ▶ Aktueller Stand (15.10.2026, Nachmittag) – hier weitermachen
- **18.10.2026 – Android-Version** (Branch `claude/clever-keller-cno24r`): `apps/android/` (Kotlin/Compose) + `core/MiniMedKitKotlin/` (Port von MiniMedKit, alle Tests grün inkl. 780G-Handshake). Baut, Screens laufen im Demo-Modus, **noch nicht an der Pumpe getestet**. ADR 0004 (vorgeschlagen), Anleitung `docs/de/android.md`. Nächster Schritt: Simon testet mit der Testpumpe (Debug-APK, Protokoll teilen).
- **16.10.2026 – Apple-Rückfrage 2.5.4** (Bluetooth-Hintergrundmodi, Prüfer ohne Pumpe): Modi bleiben, Antwort + Bildschirmaufnahme vom Koppeln/Protokoll, Text in `store-application.md` §7. **Build 4 (1.0.1)** vorbereitet: Trendpfeile in Live-Aktivität, Dynamic Island und Widgets schneiden nicht mehr ab (`TrendArrows`, `IslandValue`). **Build 4 hochgeladen 16.10. 11:08** (Release, DEV_MODE=0, keine Schlüssel-DB). Simon: Build 4 wählen, Video (Koppeln + Protokoll) an Antwort und Review-Notes, neu einreichen. Simons iPhone läuft jetzt mit der öffentlichen Variante (Release-Build).
- **App Store:** 1.0.0 (Build 2) zurückgezogen; **1.0.1 (Build 3)** hochgeladen (15.10. 14:14, Sensorstatus-Fix), Version in App Store Connect auf 1.0.1 – Simon wählt Build 3 und reicht ein. Plan für Watchfaces/Website/Apps: Obsidian „Plan Okt 2026“. Texte/Bilder DE+EN, Datenschutz („keine Daten“), Altersfreigabe, Inhaltsrechte, „kein reguliertes Medizinprodukt“, Verfügbarkeit ohne Frankreich (Verschlüsselungsantwort). Bei Rückfragen von Apple: Antworten in `store-application.md` §7.
- **18.10.2026 – Pebble-Hänger (Uhr fragt nicht mehr / aus dem Takt, bis man das Watchface neu öffnet):** Ursachen in pebble-cgm gefunden: (1) eine AppMessage ohne Rückmeldung blockierte die Sendewarteschlange der JS-Seite dauerhaft, (2) bei supercgm gingen Wert und Weckplan direkt hintereinander raus, der zweite scheiterte mit APP_MSG_BUSY, (3) verschob sich der Weckrhythmus von iPump-mini, trafen alle Anfragen das alte Fenster und der Plan wurde nie neu gelernt, (4) die BG-Anfrage der Uhr ging bei belegtem Ausgang verloren. Fix pebble-cgm 1.1.0 (Warteschlange mit Ack-Timeout, Suche alle 15 s nach verpasstem Fenster, eine Anfrage gleichzeitig, Weckplan beim Start, Anfrage mit Wiederholung). Branch `claude/adoring-bardeen-lrdbd3` in pebble-cgm, casiocgm 2.5.1 (dazu: Datumsfeld beim Schütteln), Nightscout-supercgm 2.8, dubv4cgm 1.2.1. iPump-mini selbst unverändert. **Simon testet auf der Uhr.**
- **Pebble läuft** mit casiocgm 2.4.5 (Simon bestätigt): Weckplan `ompSync`, Uhr-Taktgeber, Nightscout-Fallback mit Wolke, letzter Wert bleibt. Code: VPS `casiocgm`, Branch `feature/openminipump-source`; noch nicht im Store/main.
- **Repo öffentlich:** github.com/sgitaize/iPump-mini (Historie bereinigt). Website: simongutjahr.de/dev/ipump-mini/, Datenschutz /impressum/#ipump-mini.
- **Builds:** Release = immer öffentliche Variante. Neuer Upload: `CURRENT_PROJECT_VERSION` in `apps/ios/project.yml` erhöhen, archivieren, `xcodebuild -exportArchive` (ExportOptions: app-store-connect/upload). Texte/Bilder: `apps/ios/Scripts/asc_metadata.py` (API-Schlüssel in `~/.appstoreconnect/`).
- **Offen / Ideen:** Ergebnis App Review abwarten · TestFlight intern nutzen · AltStore Classic (Workflow „Release IPA“) und PAL · casiocgm-Version für den Store aufbereiten (Beta-Config → live) · Protokollmeldungen/Statusseite englisch · Android (JavaSake) später · Backup-Bundle `~/Dev/openMinipump-backup-20261015-0859.bundle` (alte Historie) irgendwann löschen.

## Phase 0 – Umgebung und Repo ✅
- [x] Tool-Bestand prüfen
- [x] Tools: python@3.12, apktool, adb, wireshark (CLI), mitmproxy, gitleaks, frida-tools
- [x] jadx 1.5.6, Wireshark.app
- [x] Xcode inkl. Lizenz, PacketLogger, iOS-Bluetooth-Profil (Simon)
- [x] Repo-Struktur, .gitignore, .env.example, gitleaks-Hook, README, CLAUDE.md, ADR 0001/0002
- [x] Privates GitHub-Repo sgitaize/openMinipump

## Phase 1 – Recherche ✅ (wartet auf Go)
- [x] docs/internal/landscape.md
- [x] Empfehlung: ADR 0003 (vorgeschlagen)
- [x] Simon: ADR 0003, GPL-3.0, Key-DB lokal aus _vendor/ (angenommen)
- [ ] Simon: Discord OpenMinimed beitreten / vorstellen (optional, eigener Account)

## Phase 2 – Mitschnitte ✅
- [x] Testpumpe: Seriennummer (.env) + Firmware 6.23W (Laborbuch)
- [x] PacketLogger-Mitschnitt: offizielle MiniMed Mobile koppeln + Reconnect-Tests A–D
- [ ] (Fallback) Linux-Referenz mit PythonPumpConnector, nur bei Bedarf
- [ ] Test B (außer Reichweite) bei Gelegenheit sauber wiederholen

## Phase 3 – Erste iOS-App (in Arbeit)
- [x] core/MiniMedKit: Swift-Port SAKE (AES/CMAC/SeqCrypt/Handshake), Tests gegen echten 780G-Trace
- [x] Parser: CGM-Messung, Sensorstart, IDD-Status, IOB, TIR, Algorithmus-Status, Basalrate
- [x] ReadOnlyPolicy (Allowlist) + DevModeGuard, mit Tests
- [x] iOS-App: GATT-Server (DIS 0x0900, SAKE FE82), Advertising, Handshake, GATT-Client, Werteanzeige
- [x] Kopplungsanleitung, Erinnerung bei fehlenden Daten / beendeter App
- [x] Lokale Nightscout-kompatible API (Port 17580), docs/en/api.md
- [x] Über & Impressum mit Quellenangaben
- [ ] Simon: Impressumsdaten + Website-URL bestätigen (apps/ios/OpenMinipump/UI/AboutView.swift)
- [x] Simon: Signing-Team (lokal in Local.xcconfig), App aufs iPhone
- [x] Simon: openMinipump gekoppelt, Werte kommen (14.10.)
- [x] Hardwaretest: GATT-Client-Zugriff, Handshake, Werte ✅
- [x] Hintergrund-Aktualisierung robuster (Trigger GST/Status Changed, Hänger-Erkennung, Sitzung persistiert)
- [ ] Hintergrund über mehrere Stunden prüfen (Protokolldatei vom iPhone ziehen)
- [x] Pumpenhistorie über IDD RACP (Allowlist erweitert, Simons Freigabe 15.10.): Behandlungen + Sensorwerte
- [x] Behandlungen im Graph (Bolus, KH, BZ/Kalibrierung, Pausen) + Insulin-Graph (Bolus, Auto-Basal)
- [x] Nightscout: Behandlungen hochladen (Autokorrekturen als automatic), lokale API /api/v1/treatments; fehlende Werte kommen aus der Pumpenhistorie (kein Nachladen aus Nightscout)
- [x] Einstellungen in einklappbaren Bereichen
- [x] SmartGuard-Autokorrekturen von manuellen Boli unterscheiden (Bolus Delivered P2, Aktivierungsart 0x5A)
- [x] „Fehlender“ History-Block: war doppelte Verarbeitung, behoben
- [ ] Treatments (Bolus, Kohlenhydrate) aus IDD-History

## Phase 4 – Nightscout-Upload und Pebble
- [x] Optionaler Upload (entries + devicestatus), Secret im Schlüsselbund, Verbindungstest
- [x] /pebble mit count und units=mmol
- [ ] Upload gegen Simons echtes Nightscout prüfen (Simon trägt URL/Secret in der App ein)
- [x] casiocgm 2.4.0 (Test): Datenquelle „openMinipump lokal“, Branch feature/openminipump-source, Config docs/config-beta (VPS-Projekt)
- [ ] casiocgm-Test auf der Uhr klappt noch nicht (Simon 15.10.) → später debuggen (ATS/HTTP in der Pebble-App? App im Hintergrund pausiert?)
- [x] Nightscout-Upload nur bei neuem Sensorwert, dann sofort
- [x] App-Icon (Tropfen mit CGM-Kurve, Scripts/render-icon.swift)

## Phase 5 – Alarme und Widgets (Simon 15.10., in Arbeit)
Angefangener Code liegt auf Branch **`wip/alarms-widgets`** (main bleibt baubar):
- [x] MiniMedKit: Pumpenalarme aus der History (Annunciation Consolidated 0xF010: ID, Typ, Status), Katalog `PumpAlarms` (deutsche Texte, Kategorien, „dringend“), `StatusChangedFlags` (Bit 3 = Alarmstatus geändert), Tests (30 grün)
- [x] App: `Alarms/AlarmEngine.swift` – Glukosealarme (dringend niedrig 55 mg/dL, niedrig 70, hoch 250, schnell fallend/steigend), Pumpenalarm-Kategorien, Presets (Standard / Nur dringend / Alle), Snooze-Aktionen 15/30/60 min, globales Stummschalten (außer dringend niedrig), kritisch falls verfügbar, sonst zeitkritisch
- [ ] `Watchdog.configure(enabled:minutes:)` ergänzen (Keine-Daten-Alarm aus der Alarm-Konfiguration)
- [ ] Verdrahten: `AlarmEngine.shared.evaluate` bei jedem neuen Wert (DataStore.onNewReading), `pumpAlarm(...)` in `PumpLink.processHistory` für `.annunciation`-Events, `log` setzen, `registerCategories()` + `requestAuthorization()` beim Start (ersetzt Watchdog.requestAuthorization)
- [ ] Bei IDD Status Changed mit Bit „annunciation“ sofort History abfragen (`lastHistorySync` zurücksetzen, `scheduleRefresh(force:)`)
- [ ] AppDelegate als `UNUserNotificationCenterDelegate`: Vordergrund-Anzeige (Banner + Ton), Snooze-Aktionen → `AlarmEngine.shared.snooze(key:minutes:)` (Key in userInfo „alarmKey“)
- [ ] Einstellungen: Bereich „Alarme“ (Preset-Auswahl, je Alarm Ein/Aus, Schwelle mit mmol-Anzeige, Snooze, Wiederholung; Pumpenkategorien; Test-Alarm; Hinweis kritische Alarme)
- [ ] Hauptansicht: Hinweis „Alarme stumm bis …“ + Aufheben
- [ ] Kritische Alarme: Entitlement `com.apple.developer.usernotifications.critical-alerts` bei Apple beantragen (bezahlter Account nötig); bis dahin zeitkritisch
- [ ] **Simon: in Xcode › Target › Signing & Capabilities prüfen, ob das persönliche Team „App Groups“ und „Time Sensitive Notifications“ anbietet.** Korrektur 15.10.: Die frühere Aussage „funktioniert mit dem persönlichen Team“ war falsch. XcodeGen hatte die Entitlements-Dateien leer überschrieben, deshalb lief der Build nur ohne diese Berechtigungen. Die Berechtigungen sind jetzt per `OMP_APP_ENTITLEMENTS` / `OMP_WIDGET_ENTITLEMENTS` (Base.xcconfig) schaltbar und in Simons Local.xcconfig vorerst aus.
- [x] Alarme verdrahtet (Branch `feature/alarms-widgets`): Auswertung je Wert, Pumpenalarme aus der History, sofortiger History-Abruf bei Alarm-Bit, Snooze-Aktionen, Einstellungsseite, Stumm-Banner. Im Simulator ausgelöst („Dringend niedrig 52 mg/dL“). **Bewusst noch nicht aufs iPhone gespielt** (soll Simon nachts nicht wecken), morgen gemeinsam testen.
- [x] Widgets + Live Activity gebaut (Branch `feature/alarms-widgets`): klein, mittel, groß mit Graph, Sperrbildschirm (rund, rechteckig, Zeile), Dynamic Island (kompakt Wert+Pfeil / Delta, erweitert, minimal). Live Activity startet im Simulator. Daten: App-Group-Datei, Fallback über lokalen Server (ohne App Group).
- Ursprüngliche Widget-Planung:
  - Shared-Modell (letzte Werte, Trend, Delta, IOB) als JSON in der App Group; App schreibt bei neuem Wert und ruft `WidgetCenter.reloadAllTimelines()`
  - klein: Wert + Trendpfeil + Alter; groß: zusätzlich Graph der letzten 3 h; optional Sperrbildschirm (accessory)
  - Live Activity / Dynamic Island: Wert + Trend + Delta seit letztem Wert (`NSSupportsLiveActivities`, Update aus der App bei jedem Wert; Start nur im Vordergrund möglich, Laufzeit max. 8 h → beim Öffnen neu starten)
- [ ] Insulin-Band im Glukose-Graph (gleiche Zeitachse, Antippen für Details): von Simon auf dem Gerät bestätigen lassen

## Ideen (Simon 15.10.)
- [x] Im CGM-Graph auf einen 5-Minuten-Wert tippen: Uhrzeit, SG-Wert (mg/dL + mmol/L), Trend, IOB zu diesem Zeitpunkt, Insulin und KH im 5-Minuten-Fenster (Branch `feature/alarms-widgets`; der IOB-Verlauf wird ab dieser Version gespeichert)

## Phase 6 – Veröffentlichung (nächste Schritte, Simon 15.10.)
- [ ] **Umbenennen in „iPump-mini“** (Anzeigename, Bundle-ID/Repo-Name prüfen), App-Icon und Designsprache passend dazu entwickeln
- [ ] App grafisch aufwerten: schlicht, aber schick, ohne generischen „AI-Look“
- [ ] Entwickler-Website (simongutjahr.de / Dev-Portfolio) um openMinipump ergänzen, **ganz oben platzieren**
- [ ] GitHub-Repo öffentlich machen: README (EN/DE), Build-Anleitung für den Selbstbau
  - vorher: Git-Historie von den versehentlich eingecheckten SwiftPM-Build-Dateien bereinigen (Commit d9ab5a1, ~227 MB)
  - vorher: rechtliche Prüfung (Interoperabilität §69e UrhG, Markenhinweise, Haftungsausschluss), Umgang mit der Kompatibilitäts-Kennung `compatSoftwareRevision`
  - Schlüsseldatenbank bleibt draußen; Anleitung, wie man sie sich selbst beschafft (OpenMinimed-Doku)
- [ ] AltStore-Veröffentlichung vorbereiten: Source-JSON (apps.json), signierte IPA als GitHub-Release-Asset, GitHub-Actions-Pipeline (Build → IPA → Release → Source aktualisieren)


## Phase 7 – Android (18.10.2026, wartet auf Hardwaretest)
- [x] `core/MiniMedKitKotlin`: Kotlin-Port (SAKE, SeqCrypt, Key-DB, Parser, History, Allowlist, DevModeGuard, Nightscout, Alarmtabelle), gleiche Testvektoren wie Swift
- [x] `apps/android`: GATT-Server (SAKE FE82, DIS 0x0900), Advertising (Herstellerdaten 0x01F9 mit „Mobile …“), GATT-Client auf der Pumpenverbindung, Abfragezyklus, History
- [x] Vordergrunddienst mit Wert in der Mitteilung, Boot-Start, Alarme, Nightscout, lokale API + Statusseite, Demo-Modus, Onboarding, DE/EN
- [x] Screens per Robolectric gerendert (`./gradlew :app:testDebugUnitTest -Pscreenshots=…`), CI-Workflow `android.yml`
- [ ] Simon: ADR 0004 bestätigen
- [ ] Simon: Debug-APK auf Android-Handy, Kopplung mit Testpumpe, Protokoll teilen (Ablauf in `docs/de/android.md`)
- [ ] Prüfen: Name in den Herstellerdaten sichtbar? DIS-Werte akzeptiert? GATT-Client hängt sich an die bestehende Verbindung?
- [ ] Hintergrund über Stunden (Doze, Hersteller-Akkusparen)
- [ ] Simon: Release-Keystore lokal erzeugen und sichern (nie ins Repo/Chat)
- [ ] Später: Widgets (Glance), Release-Pipeline (signierte APK), F-Droid/GitHub Releases

## Nachtarbeit 15.10.2026 (01:08–01:30, Simon schläft, Freigabe „selbstständig nach Plan“)
- 01:08 Neukopplung durch Simon nach dem Verbindungsfehler: läuft, Werte alle 5 min im Hintergrund, Nightscout-Upload ok (main-Build auf dem iPhone).
- Branch **`feature/alarms-widgets`** (gepusht, **nicht auf dem iPhone**, nicht nach main gemergt):
  - Alarme komplett verdrahtet + Einstellungsseite, im Simulator ausgelöst
  - Widgets (klein/mittel/groß/Sperrbildschirm) + Live Activity/Dynamic Island, Live Activity startet im Simulator
  - Tippen auf Sensorwert → Details mit IOB-Verlauf und Abgaben im 5-min-Fenster
  - Import der Schlüsseldatenbank in der App (für spätere öffentliche Builds)
  - README + Build-Anleitung, AltStore-Vorbereitung (`docs/internal/release-altstore.md`, `altstore/source.json`, manuelle Draft-Pipeline)
- Designvorschlag iPump-mini: `docs/internal/design/ipump-mini.md`, `docs/internal/design/icon-proposals.png` (Empfehlung Variante A)
- Website: Entwurf der openMinipump-Karte (oben auf /dev/) im VPS-Projekt `simongutjahr-website/drafts/`, **nicht deployt**
- **Für Simon am Morgen:**
  1. In Xcode mit angemeldetem Account Signing & Capabilities prüfen (App Groups, Time Sensitive). Falls verfügbar, in `Local.xcconfig` die zwei leeren `OMP_*_ENTITLEMENTS`-Zeilen entfernen.
  2. Branch `feature/alarms-widgets` gemeinsam aufs iPhone spielen und testen (Alarme, Widgets, Dynamic Island), dann nach main mergen.
  3. Icon-Variante und Namen entscheiden.
  4. Freigabe für die Website-Karte und den Zeitpunkt „Repo öffentlich“.
- **Morgen 15.10. erledigt:** Simon hat geprüft: das kostenlose Team bietet App Groups (App und Widget), aber **keine** zeitkritischen Mitteilungen. Standard-Entitlements jetzt nur App Group, `OpenMinipump-paid.entitlements` mit Time Sensitive für bezahlte Teams. Alarme kommen beim kostenlosen Team als normale Mitteilungen (Hinweis in den Alarm-Einstellungen). Icon Variante A umgesetzt, Anzeigename „iPump-mini“ (Bundle-ID unverändert).
  - Offen: neues Profil mit App Group braucht einmal **Run in Xcode** (Kommandozeile hat keinen Account), danach Test von Alarmen, Widgets, Dynamic Island auf dem iPhone, dann Merge nach main.

## 15.10.2026, erster Upload zu App Store Connect
- App in App Store Connect angelegt (Simon). Build **1.0.0 (2)** als Release-Archiv (öffentliche Variante) per `xcodebuild -exportArchive` (method app-store-connect, destination upload) hochgeladen, 13:23. Nächste Builds: `CURRENT_PROJECT_VERSION` in `apps/ios/project.yml` erhöhen.
- Offen: Export-Compliance in TestFlight beantworten (Vorschlag `docs/internal/store-application.md` §9), interne Tester, Installation über TestFlight; danach Metadaten/Screenshots und Einreichung.
- Release-Builds sind jetzt immer öffentlich (embed-local-config.sh), auch aus Xcode.
- casiocgm 2.4.5 bei Simon zum Test (Uhr-Taktgeber, Fallback, Wolke).

## 15.10.2026, öffentliche Variante auf Simons iPhone
- Release-Build mit `OMP_PUBLIC_BUILD=1 OMP_PUBLIC_DEV_MODE=0` (keine Schlüsseldatenbank, keine Seriennummer) installiert, ersetzt den Entwickler-Build. Zurück zum Entwickler-Build: normaler `xcodebuild … build` + Installation. Test: Schlüsseldatenbank über „Von OpenMinimed laden“.
- casiocgm 2.4.3: Nightscout-Fallback im Emulator geprüft (ein NS-Abruf nach ~7 min ohne lokalen Server, Wert angezeigt).

## To-do Veröffentlichung (Simon 15.10.: App Store, TestFlight, AltStore Classic und PAL – alles probieren)
- Texte und Anträge: `docs/internal/store-application.md` (Beschreibungen DE/EN, Review-Notes, TestFlight, kritische Alarme, AltStore, Rückfragen).
- Code sauber dokumentieren: Kommentare sind bereits englisch (1 Zeile deutsch); fehlt: Doku-Kommentare öffentlicher Typen (MiniMedKit, App-Kerne), `docs/en/architecture.md`, Protokollmeldungen und API-Statusseite englisch bzw. lokalisiert.
- Demo-Modus für App Review in Release-Builds, Datenschutzerklärung für die App, Store-Screenshots, Export-Compliance.

## 15.10.2026, Pebble und Widgets
- Lokale API im Hintergrund: iOS nimmt dem pausierten Server den Socket (Listener bleibt „ready“, Verbindungen abgelehnt) → `revive()` startet ihn bei jedem Pumpen-Wecken neu, Hintergrund-Task hält ihn ~25 s offen (gemessen: 30 s Fenster alle 5:00). `/pebble` liefert `ompSync` (Weckplan). Pebble-App (ktor-client) erreicht den Server, ATS ist kein Problem. Anstupsen von der Uhr aus geht nicht zuverlässig (nur stille Pushes).
- casiocgm 2.4.2 (VPS, Branch feature/openminipump-source): fragt nach Weckplan ab, letzter Wert bleibt über Neustarts. Im Emulator geprüft; Simon testet auf der Uhr (`~/Downloads/casiocgm-2.4.2-openminipump-beta.pbw`).
- Home-Widget: Budget ~40–70 Reloads/Tag → im Hintergrund nur noch bei Tiefs, Bereichswechsel, ≥ 10 mg/dL oder alle 20 min; im Vordergrund immer.

## 15.10.2026, bezahlter Apple-Developer-Account
- Simon ist (wieder) im Apple Developer Program, gleiche Team-ID `V7GQKCH73F`. `Local.xcconfig` nutzt jetzt `OpenMinipump-paid.entitlements` (zeitkritische Mitteilungen + App Group). Profil gültig bis 15.10.2027, Bundle-ID unverändert, Sitzung zur Pumpe blieb bestehen.
- Offen: kritische Alarme bei Apple beantragen (Formular „Critical Alerts Entitlement“), danach Entitlement ergänzen. TestFlight, AltStore PAL (Notarisierung) als nächste Wege; App Store für iPump-mini erst nach rechtlicher Einschätzung (MDR).
- Pebble/casiocgm 2.4.1-Testbuild (VPS, Branch feature/openminipump-source): langer Request-Timeout, schnelle Wiederholung; App hält API 25 s wach und protokolliert Anfragen. Simon testet auf der Uhr.

## 15.10.2026, Veröffentlichung Repo
- Simon: Freigabe öffentliche Builds für alle 780G (`allow_any_pump`, Standard an). Doku nach Sprachen getrennt (`docs/en`, `docs/de`, `docs/internal`).
- Historie bereinigt (git filter-repo): Build-Artefakte entfernt (76 → 2 MB), Pumpen-Seriennummer im Kommentar ersetzt; Prüfung aller Commits: keine Schlüssel, Secrets, Hosts, Adressen. Backup: `~/Dev/openMinipump-backup-20261015-0859.bundle`.
- GitHub-Repo gelöscht und neu angelegt (Simons Wahl), bereinigte Historie gepusht, **öffentlich**: https://github.com/sgitaize/iPump-mini. Secret Scanning + Push Protection an. Weiterleitung vom alten Namen openMinipump entfällt.
- Website: GitHub-Links auf /dev/ und /dev/ipump-mini/ ergänzt, deployt.
- AltStore: Empfehlung Classic (kostenlos, weltweit, ohne Apple-Prüfung). PAL bräuchte bezahlten Account + Notarisierung (nur EU/JP/BR). Entscheidung Simon offen.
- Nächster Schritt: Probelauf des Release-Workflows (Entwurf), IPA per AltStore installieren, dann `altstore/source.json` veröffentlichen (z. B. GitHub Pages) und Release freigeben.

## 15.10.2026, später Vormittag
- Nutzungsbedingungen von Simon freigegeben; `feature/onboarding-l10n` nach main gemergt (`53e3a56`), main ist auf Simons iPhone.
- Impressum in der App wie auf simongutjahr.de (Simon Gutjahr, Anschrift, Mail, Telefon, Link zu /impressum/ und /dev/).
- GitHub-Repo umbenannt: **sgitaize/iPump-mini** (privat, alte URLs leiten weiter; Remote auf HTTPS). Beschreibung, Website, Topics gesetzt. Lokaler Ordner bleibt `~/Dev/openMinipump`, Xcode-Target/Bundle-ID bleiben.
- README neu (Englisch, `README.de.md` Deutsch) mit Screenshots aus Demo-Daten (`docs/images/`, Debug `-screenshot`), Bauanleitung `docs/en/building.md` (en) / `docs/de/selbst-bauen.md` (de).
- Website live: Karte „Aktuelles Projekt“ ganz oben auf simongutjahr.de/dev/ und Projektseite /dev/ipump-mini/ (DE/EN, Bilder, Get started, Hinweis); Impressum-Geltungsbereich um die App ergänzt. **Ohne GitHub-Link**, solange das Repo privat ist.
- Offen für die Veröffentlichung: `allow_any_pump`/DEV_MODE, Kompatibilitäts-Kennung, Git-Historie bereinigen, Repo öffentlich, Probelauf Workflow → dann GitHub-Links auf Website und in der App-Karte ergänzen.

## Vormittag 15.10.2026 (Simon testet mit)
- Alarme, Widgets, Test-Alarm auf dem iPhone von Simon bestätigt → `feature/alarms-widgets` nach main gemergt (`051e6ad`).
- Branch **`feature/onboarding-l10n`** (gepusht, auf Simons iPhone installiert, App Group aktiv):
  - Ersteinrichtung: Sprache, **Nutzungsbedingungen mit Haftungsausschluss** (Pflicht, versioniert: `Terms.version`), Checkliste (Schlüsseldatenbank, Mitteilungen, Sensor, Koppeln), Fallstricke zu Mitteilungen. Anleitung und Bedingungen unter Einstellungen › Info.
  - **Schlüsseldatenbank laden**: „Von OpenMinimed laden“ (öffentliche key_databases.md), eigene URL oder Einfügen; `KeyDatabase.findHex` mit Test gegen die echte Seite.
  - **Aussehen**: Hell/Dunkel/System, Sprache, mg/dL oder mmol/L, Zielbereich; Akzentfarbe Petrol.
  - **Widgets** überarbeitet (Kurve, Statuszeile, Stil schlicht/farbig, 3/6 h, Sperrbildschirm mit Kurve und IOB), Live-Aktivität mit Bereichsfarbe und IOB, Debug-Galerie `-widgetGallery`.
  - **Englisch** (383 Texte, `docs/en/translating.md`), Umschalter in der App, Erkennung der Gerätesprache.
  - **Graph durchwischen**: waagerecht wischen bewegt die Auswahl, letzte bleibt stehen.
  - `docs/en/getting-started.md` (de/en), README aktualisiert; Website-Entwurf auf dem VPS aktualisiert (nicht live).
  - Release-Pipeline: öffentlicher Build ohne `.env`/Schlüsseldatenbank (Prüfschritt), Ad-hoc-Signatur mit App Group, Eingabe `allow_any_pump` (Standard gesperrt).
- Schlüsseldatenbank zusätzlich gesichert: macOS-Schlüsselbund (Account `sakeKeyDatabase`) und iCloud Drive `openMinipump-Backup/` (mit LIESMICH). Identisch mit dem OpenMinimed-Block.
- **Offen / für Simon:**
  1. Branch testen (Ersteinrichtung, Englisch, Dunkelmodus, Widgets, Wischen im Graphen), dann nach main mergen.
  2. Nutzungsbedingungen inhaltlich prüfen (Entwurf, keine Rechtsberatung).
  3. Entscheidungen für die Veröffentlichung: `allow_any_pump`/DEV_MODE, Kompatibilitäts-Kennung, Repo öffentlich (Historie bereinigen), Probelauf des Workflows.
  4. Statusseite der lokalen API (`StatusPage.swift`) ist noch nur deutsch.

## Stand am Ende der Sitzung (15.10.2026, ~00:50)
- main (`bb71a98`) ist auf Simons iPhone installiert und läuft: Werte, Historie, Behandlungen, Nightscout, API, antippbarer Insulin-Graph.
- Offene Arbeit: Phase 5 (Branch `wip/alarms-widgets`), Phase 6 (Veröffentlichung), Pebble-Test debuggen.
- Weitermachen: `git checkout wip/alarms-widgets`, Punkte oben abarbeiten, `cd apps/ios && xcodegen`, bauen, installieren (`xcrun devicectl device install app …`), dann nach main mergen.
