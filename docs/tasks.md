# Aufgabenliste

## Phase 0 – Umgebung und Repo ✅
- [x] Tool-Bestand prüfen
- [x] Tools: python@3.12, apktool, adb, wireshark (CLI), mitmproxy, gitleaks, frida-tools
- [x] jadx 1.5.6, Wireshark.app
- [x] Xcode inkl. Lizenz, PacketLogger, iOS-Bluetooth-Profil (Simon)
- [x] Repo-Struktur, .gitignore, .env.example, gitleaks-Hook, README, CLAUDE.md, ADR 0001/0002
- [x] Privates GitHub-Repo sgitaize/openMinipump

## Phase 1 – Recherche ✅ (wartet auf Go)
- [x] docs/landscape.md
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
- [x] Lokale Nightscout-kompatible API (Port 17580), docs/api.md
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
- [ ] Kritische Alarme: Entitlement `com.apple.developer.usernotifications.critical-alerts` bei Apple beantragen (bezahlter Account nötig); bis dahin zeitkritisch (Entitlement ist bereits aktiv und funktioniert mit dem persönlichen Team)
- [ ] Widgets (Extension-Gerüst + App Group `group.<bundle id>` sind auf main und signieren mit dem persönlichen Team):
  - Shared-Modell (letzte Werte, Trend, Delta, IOB) als JSON in der App Group; App schreibt bei neuem Wert und ruft `WidgetCenter.reloadAllTimelines()`
  - klein: Wert + Trendpfeil + Alter; groß: zusätzlich Graph der letzten 3 h; optional Sperrbildschirm (accessory)
  - Live Activity / Dynamic Island: Wert + Trend + Delta seit letztem Wert (`NSSupportsLiveActivities`, Update aus der App bei jedem Wert; Start nur im Vordergrund möglich, Laufzeit max. 8 h → beim Öffnen neu starten)
- [ ] Insulin-Band im Glukose-Graph (gleiche Zeitachse, Antippen für Details): von Simon auf dem Gerät bestätigen lassen

## Phase 6 – Veröffentlichung (nächste Schritte, Simon 15.10.)
- [ ] App grafisch aufwerten: schlicht, aber schick, ohne generischen „AI-Look“
- [ ] Entwickler-Website (simongutjahr.de / Dev-Portfolio) um openMinipump ergänzen, **ganz oben platzieren**
- [ ] GitHub-Repo öffentlich machen: README (EN/DE), Build-Anleitung für den Selbstbau
  - vorher: Git-Historie von den versehentlich eingecheckten SwiftPM-Build-Dateien bereinigen (Commit d9ab5a1, ~227 MB)
  - vorher: rechtliche Prüfung (Interoperabilität §69e UrhG, Markenhinweise, Haftungsausschluss), Umgang mit der Kompatibilitäts-Kennung `compatSoftwareRevision`
  - Schlüsseldatenbank bleibt draußen; Anleitung, wie man sie sich selbst beschafft (OpenMinimed-Doku)
- [ ] AltStore-Veröffentlichung vorbereiten: Source-JSON (apps.json), signierte IPA als GitHub-Release-Asset, GitHub-Actions-Pipeline (Build → IPA → Release → Source aktualisieren)

## Stand am Ende der Sitzung (15.10.2026, ~00:50)
- main (`bb71a98`) ist auf Simons iPhone installiert und läuft: Werte, Historie, Behandlungen, Nightscout, API, antippbarer Insulin-Graph.
- Offene Arbeit: Phase 5 (Branch `wip/alarms-widgets`), Phase 6 (Veröffentlichung), Pebble-Test debuggen.
- Weitermachen: `git checkout wip/alarms-widgets`, Punkte oben abarbeiten, `cd apps/ios && xcodegen`, bauen, installieren (`xcrun devicectl device install app …`), dann nach main mergen.
