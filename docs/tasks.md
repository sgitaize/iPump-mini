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

## Phase 5 – Alarme und Widgets (Simon 15.10.)
- [ ] Benachrichtigungen mit Stummschalten (Snooze) wie in CGM-Apps
- [ ] Dringend niedrig (55 mg/dL / 3,1 mmol/L) als kritischer Alarm (braucht Apple-Freigabe, sonst „zeitkritisch“)
- [ ] Pumpenalarme (Annunciations) weitergeben, einzeln konfigurierbar, Presets
- [ ] Widgets: klein (Wert + Trend), groß (mit Graph), Live Activity / Dynamic Island (Wert, Trend, Delta)
