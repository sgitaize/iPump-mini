# CLAUDE.md – openMinipump

Der vollständige Projekt-Brief steht in `docs/project-brief.md`. Er ist verbindlich, lies ihn zu Beginn jeder Session.

## Ziel
Eine quelloffene iOS- und Android-App liest eine MiniMed 780G **nur lesend** per BLE aus und stellt die Daten lokal per REST-API bereit, ohne CareLink-Cloud. Später sollen die Daten auch in Simons Nightscout bzw. supercgm fließen. **Der Fokus liegt aktuell auf iOS.**

## Harte Regeln (nicht verhandelbar)
1. **Nur lesen.** Der Protokoll-Client nutzt eine Opcode-Allowlist. Alles andere wird hart blockiert und geloggt. Im Zweifel gilt eine Nachricht als verboten, dann Simon fragen.
2. **Nur das Testgerät.** Bei `DEV_MODE=1` wird jede Seriennummer außer `TEST_PUMP_SERIAL` (aus `.env`) abgelehnt.
3. **Kein proprietäres Material im Repo.** APK/IPA, Dekompilate, Keys, Zertifikate und Assets gehören nach `_vendor/` (gitignored). Ins Repo kommen nur eigene Worte und eigener Code (Clean Room).
4. **Secrets nie in Git.** Dafür gibt es `.env`, den Schlüsselbund und gitignorierte Ordner. Der Pre-Commit-Hook (`.githooks/pre-commit`) führt gitleaks aus.
5. **Medtronic-Server:** Mitschnitte eigener Sitzungen sind erlaubt. Keine Angriffe, kein Fuzzing. Eigene Requests nur nach Rückfrage.
6. **Vor irreversiblen oder riskanten Schritten fragen** (Firmware, Werksreset, Root/Jailbreak, Frida-Pinning-Bypass).

## Arbeitsweise
- Gearbeitet wird in Phasen. Am Ende jeder Phase gibt es eine Zusammenfassung, dann wird auf Simons Go gewartet.
- Aufgaben: `docs/tasks.md`. Laborbuch: `docs/lab-notebook.md`. ADRs: `docs/decisions/NNNN-*.md`. Protokoll: `docs/protocol/`.
- Conventional Commits, Push nach jedem abgeschlossenen Schritt. Commit-Mail ist die GitHub-noreply-Adresse (lokal konfiguriert).
- Physische Schritte an der Pumpe macht Simon. Sag ihm jeweils genau, was er wann tun soll.

## Repo-Struktur
`docs/` Wissen · `research/` eigene Skripte · `captures/` (ignored) Mitschnitte · `_vendor/` (ignored) Vendor-Material · `proto/` Referenz/Prototypen (bleak entfällt, siehe ADR 0003) · `core/` gemeinsame Protokoll-Lib · `apps/ios/` SwiftUI · `apps/android/` Kotlin

## Umgebung
- Repo: `~/Dev/openMinipump` (bewusst nicht in iCloud, siehe ADR 0001), GitHub: `sgitaize/openMinipump` (privat)
- Der iOS-Simulator hat kein Bluetooth, deshalb braucht es einen Replay-Transport aus echten Mitschnitten.

## Aktueller Stand
- Phase 0–2 ✅ (Recherche, ADR 0003, GPL-3.0, Mitschnitte der offiziellen App). Phase 3 läuft: erste iOS-App gebaut, **Hardwaretest steht aus**.
- `core/MiniMedKit` (Swift-Paket): SAKE-Port, Parser, `ReadOnlyPolicy` (die Allowlist, Änderungen nur mit Simon), `DevModeGuard`, Nightscout-Mapping. `swift test` prüft den Handshake gegen den echten 780G-Trace (Key-DB aus `_vendor/keys/`, sonst Skip).
- `apps/ios`: XcodeGen (`project.yml`), Setup in `docs/setup-ios.md`. Alle Schreibzugriffe auf die Pumpe laufen über `PumpLink.guardedWrite`. API: `docs/api.md`.
- Kernwissen: `docs/landscape.md`, Laborbuch. Die Pumpe ist Central und SAKE-Client, das Telefon Peripheral und SAKE-Server und zusätzlich GATT-Client auf derselben Verbindung. Dauerverbindung, Reconnect über den Bond.
- Offene Risiken: GATT-Client-Zugriff unter iOS (`retrievePeripherals`/`retrieveConnectedPeripherals`) noch unbewiesen. API unter iOS im Hintergrund nicht erreichbar, daher Nightscout-Upload als Phase 4.
