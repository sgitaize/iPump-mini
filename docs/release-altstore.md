# Veröffentlichung über AltStore (Vorbereitung)

Stand: vorbereitet, **nicht aktiv**. Bevor etwas veröffentlicht wird, entscheidet Simon über die offenen Punkte unten.

## Wie AltStore funktioniert
- AltStore (bzw. SideStore) installiert IPA-Dateien auf dem iPhone und signiert sie dabei mit der **Apple-ID des Nutzers** neu. Mit kostenloser Apple-ID läuft die App 7 Tage; AltStore erneuert das automatisch, solange AltServer (Mac/PC) im selben WLAN läuft.
- Apps werden über eine **Quelle** verteilt: eine JSON-Datei (`altstore/source.json`), die Name, Bundle-ID, Versionen und Download-URLs der IPA enthält. Nutzer fügen die URL der Quelle in AltStore hinzu und bekommen Updates automatisch angezeigt.
- Die IPA muss **nicht** von uns signiert sein; AltStore signiert sie beim Installieren.
- Einschränkungen kostenloser Apple-IDs: höchstens 3 aktive Apps und 10 App-IDs pro Woche. App plus Widget-Erweiterung belegen 2 App-IDs. App Groups und manche Berechtigungen stehen evtl. nicht zur Verfügung; die App funktioniert dann ohne (Widgets über den lokalen Server).

## Pipeline (GitHub Actions)
`.github/workflows/release.yml` – nur **manuell** startbar (Actions › „Release IPA“ › Run workflow):
1. macOS-Runner, XcodeGen, Release-Build ohne Signatur. `OMP_PUBLIC_BUILD=1` sorgt dafür, dass `embed-local-config.sh` weder `.env` noch die Schlüsseldatenbank übernimmt.
2. **Prüfschritt:** Bricht ab, wenn eine Schlüsseldatenbank oder eine Test-Seriennummer im Paket liegt.
3. **Ad-hoc-Signatur mit Berechtigungen** (App Group für App und Widget). AltStore liest daraus, welche App Group es mit der Apple-ID des Nutzers anlegen muss. AltStore benennt Bundle-ID und Gruppe dabei um; die App sucht deshalb zur Laufzeit auch `group.<aktuelle Bundle-ID>` (`SharedStore.groupID`). Auf einem echten AltStore-Gerät noch nicht getestet.
4. `Payload/OpenMinipump.app` → `iPump-mini-<version>.ipa`, dazu `source.json` mit Version, Datum, Größe und Download-URL.
5. GitHub-Release als **Entwurf** (erst durch manuelles Veröffentlichen sichtbar).

Eingabe **`allow_any_pump`** (Standard: aus): aus = gesperrter Build (`DEV_MODE=1` ohne Testpumpe, lehnt jede Pumpe ab), an = `DEV_MODE=0`. Anschalten nur mit Simons Freigabe.

Die Quelle könnte später über GitHub Pages ausgeliefert werden (`https://<user>.github.io/<repo>/altstore/source.json`); dafür muss das Repo öffentlich sein.

## Offene Entscheidungen vor einer Veröffentlichung
- [x] **Schlüsseldatenbank:** nicht im Repo und nicht in der IPA. Die App lädt sie auf Knopfdruck von der öffentlichen OpenMinimed-Dokumentation (Einstellungen › Pumpe › Schlüsseldatenbank, auch in der Ersteinrichtung), alternativ von einer eigenen URL oder per Einfügen. Prüfung: CRC und richtiger Gerätetyp; Speicherung im Schlüsselbund.
- [x] **Name:** „iPump-mini“ als Anzeigename, Bundle-ID bleibt `de.sgitaize.openminipump`.
- [x] **Nutzungsbedingungen:** müssen beim ersten Start akzeptiert werden (`TermsView.swift`, versioniert). Text ist ein Entwurf, keine Rechtsberatung.
- [ ] **DEV_MODE:** Öffentliche Builds müssen jede (vom Nutzer gekoppelte) Pumpe akzeptieren, also `allow_any_pump`. Regel 2 des Projekt-Briefs gilt für die Entwicklung; Freigabe durch Simon nötig.
- [ ] **Kompatibilitäts-Kennung:** Die App meldet sich gegenüber der Pumpe mit den Geräteinfos der offiziellen App (`PumpLink.compatSoftwareRevision`). Rechtliche Einschätzung vor Veröffentlichung.
- [ ] **Repo öffentlich:** vorher Git-Historie von den Build-Artefakten bereinigen (siehe `docs/tasks.md`).
- [ ] **Probelauf:** Workflow einmal im privaten Repo starten (erzeugt nur einen Entwurf) und die IPA per AltStore installieren.
