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
- [ ] Simon: Signing-Team in apps/ios/Config/Local.xcconfig, App aufs iPhone
- [ ] Simon: MiniMed Mobile an der Pumpe entkoppeln, openMinipump koppeln (erster Hardwaretest)
- [ ] Hardwaretest auswerten: GATT-Client-Zugriff, Handshake, Werte, Hintergrund, Reconnect
- [ ] Backfill: CGM-Historie per RACP nach Reconnect
- [ ] Treatments (Bolus, Kohlenhydrate) aus IDD-History

## Phase 4 – Nightscout-Upload (geplant)
- [ ] Upload zu Simons Nightscout bei jedem BLE-Ereignis (funktioniert auch im Hintergrund)
- [ ] Secrets im Schlüsselbund
