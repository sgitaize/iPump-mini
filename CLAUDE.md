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
- Repo: `~/Dev/openMinipump` (bewusst nicht in iCloud, siehe ADR 0001), GitHub: `sgitaize/iPump-mini` (privat; bis 15.10. `openMinipump`, GitHub leitet weiter)
- Der iOS-Simulator hat kein Bluetooth, deshalb braucht es einen Replay-Transport aus echten Mitschnitten.

## Aktueller Stand
- Phase 3/4: Die iOS-App läuft auf Simons iPhone mit der Testpumpe. Werte, Pumpenstatus, Pumpenhistorie (Behandlungen), Hintergrundbetrieb, Nightscout-Upload/-Nachladen, lokale API mit Statusseite. Offene Punkte: `docs/tasks.md`.
- `core/MiniMedKit` (Swift-Paket): SAKE-Port, Parser inkl. History, `ReadOnlyPolicy` (Allowlist, Änderungen nur mit Simon; letzte Freigabe 15.10.: IDD-RACP-Report-Befehle), `DevModeGuard`, Nightscout-Mapping. `swift test` prüft den Handshake gegen den echten 780G-Trace.
- `apps/ios`: XcodeGen, Setup `docs/setup-ios.md`, Signing lokal in `Config/Local.xcconfig`. Alle Schreibzugriffe auf die Pumpe laufen über `PumpLink.guardedWrite`. Protokolldatei auf dem iPhone: `Application Support/openminipump.log` (per `xcrun devicectl device copy from … --domain-type appDataContainer`).
- Erkenntnisse im Laborbuch: DIS-Werte wie die offizielle App, 5-min-Trigger (GST Battery + IDD Status Changed), Sitzung wird gespeichert, ohne Sitzung GATT-Dienste neu registrieren, CGM-RACP „≥ Offset“ nicht unterstützt.
- Anzeigename **iPump-mini** (Bundle-ID bleibt). Alarme/Widgets sind in main. In Arbeit: Branch `feature/onboarding-l10n` (Ersteinrichtung mit Nutzungsbedingungen, Englisch, Aussehen, Widgets neu, Release-Pipeline), Stand in `docs/tasks.md` („Vormittag 15.10.“).
- Sprachen: Deutsch ist Quellsprache, Übersetzungen in `Shared/Localizable.xcstrings`; neue Texte → `docs/localization.md`. Texte aus Code über `L10n.tr`.
- Signing: kostenloses Team kann App Groups, keine zeitkritischen Mitteilungen. Neue Berechtigungen brauchen einmal ⌘R in Xcode (Profil), danach geht die Kommandozeile.
- Installieren aufs iPhone ohne Xcode-GUI: `xcodebuild -project apps/ios/OpenMinipump.xcodeproj -scheme OpenMinipump -destination 'id=<UDID>' -allowProvisioningUpdates build`, dann `xcrun devicectl device install app --device <UDID> <…/Debug-iphoneos/OpenMinipump.app>`. Simon lässt die App laufen; die Sitzung zur Pumpe wird über Updates hinweg fortgesetzt.
- casiocgm-Testversion mit Datenquelle openMinipump: VPS-Projekt `casiocgm`, Branch `feature/openminipump-source`; auf der echten Uhr noch nicht funktionsfähig.
