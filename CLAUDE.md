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
- Phase 0 ✅. Phase 1 (Recherche) ✅, ADR 0003 angenommen, Lizenz GPL-3.0. Nächster Schritt: PacketLogger-Mitschnitt der offiziellen MiniMed Mobile auf Simons iPhone 18 Pro, danach der Swift-Spike.
- Kernwissen: `docs/landscape.md`. Das Protokoll ist durch OpenMinimed (GPL-3.0) bekannt, das Telefon ist BLE-**Peripheral** und SAKE-Server, die Pumpe ist Central. Pairing läuft lokal ohne Cloud. Für iOS existiert noch nichts.
- Größte Risiken für iOS: Hintergrund-Reconnect (FE81), GATT-Client auf einer eingehenden Verbindung, MTU 23.
