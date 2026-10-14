# Aufgabenliste

## Phase 0 – Umgebung und Repo ✅
- [x] Tool-Bestand prüfen
- [x] Tools: python@3.12, apktool, adb, wireshark (CLI), mitmproxy, gitleaks, frida-tools
- [ ] jadx, Wireshark.app (Nachinstallation läuft)
- [x] Xcode inkl. Lizenz, PacketLogger, iOS-Bluetooth-Profil (Simon)
- [x] Repo-Struktur, .gitignore, .env.example, gitleaks-Hook, README, CLAUDE.md, ADR 0001/0002
- [x] Privates GitHub-Repo sgitaize/openMinipump

## Phase 1 – Recherche ✅ (wartet auf Go)
- [x] docs/landscape.md
- [x] Empfehlung: ADR 0003 (vorgeschlagen)
- [x] Simon: ADR 0003, GPL-3.0, Key-DB lokal aus _vendor/ (angenommen)
- [ ] Simon: Discord OpenMinimed beitreten / vorstellen (optional, eigener Account)

## Phase 2/3 – neu zugeschnitten (Vorschlag)
- [ ] Testpumpe: Seriennummer + Firmware-Version ins Laborbuch / .env
- [ ] (Fallback) Linux-Referenz mit PythonPumpConnector, nur bei Bedarf
- [ ] PacketLogger-Mitschnitt: offizielle MiniMed Mobile (iOS) koppeln + Reconnect im Hintergrund
- [ ] Swift-Spike (macOS-CLI → iPhone): Advertising FE82, GATT-Server, retrieveConnectedPeripherals
