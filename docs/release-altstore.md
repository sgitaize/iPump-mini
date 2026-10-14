# Veröffentlichung über AltStore (Vorbereitung)

Stand: vorbereitet, **nicht aktiv**. Bevor etwas veröffentlicht wird, entscheidet Simon über die offenen Punkte unten.

## Wie AltStore funktioniert
- AltStore (bzw. SideStore) installiert IPA-Dateien auf dem iPhone und signiert sie dabei mit der **Apple-ID des Nutzers** neu. Mit kostenloser Apple-ID läuft die App 7 Tage; AltStore erneuert das automatisch, solange AltServer (Mac/PC) im selben WLAN läuft.
- Apps werden über eine **Quelle** verteilt: eine JSON-Datei (`altstore/source.json`), die Name, Bundle-ID, Versionen und Download-URLs der IPA enthält. Nutzer fügen die URL der Quelle in AltStore hinzu und bekommen Updates automatisch angezeigt.
- Die IPA muss **nicht** von uns signiert sein; AltStore signiert sie beim Installieren.
- Einschränkungen kostenloser Apple-IDs: höchstens 3 aktive Apps und 10 App-IDs pro Woche. App plus Widget-Erweiterung belegen 2 App-IDs. App Groups und manche Berechtigungen stehen evtl. nicht zur Verfügung; die App funktioniert dann ohne (Widgets über den lokalen Server).

## Pipeline (GitHub Actions)
`.github/workflows/release.yml` – nur **manuell** startbar (Actions › „Release IPA“ › Run workflow):
1. macOS-Runner, XcodeGen, Build ohne Signatur (`CODE_SIGNING_ALLOWED=NO`) im Release-Modus.
2. `Payload/OpenMinipump.app` → `OpenMinipump-<version>.ipa`.
3. GitHub-Release als **Entwurf** mit der IPA als Asset (wird erst durch manuelles Veröffentlichen sichtbar).
4. `altstore/source.json` wird mit Version, Datum, Größe und Download-URL aktualisiert (als Artefakt; Commit/Pages-Veröffentlichung manuell).

Die Quelle könnte später über GitHub Pages ausgeliefert werden (`https://<user>.github.io/<repo>/altstore/source.json`); dafür muss das Repo öffentlich sein.

## Offene Entscheidungen vor einer Veröffentlichung
- [x] **Schlüsseldatenbank:** Sie darf nach unseren Regeln nicht ins Repo und auch nicht in eine öffentliche IPA. Umgesetzt (Branch `feature/alarms-widgets`): Einstellungen › Pumpe › Schlüsseldatenbank. Hex einfügen, Prüfung (CRC, richtige Datenbank), Speicherung im Schlüsselbund. Eigene Builds nutzen weiterhin die Datei aus `_vendor/`.
- [ ] **DEV_MODE:** Öffentliche Builds müssen jede (vom Nutzer gekoppelte) Pumpe akzeptieren, also `DEV_MODE=0`. Regel 2 des Projekt-Briefs gilt für die Entwicklung; Freigabe durch Simon nötig.
- [ ] **Kompatibilitäts-Kennung:** Die App meldet sich gegenüber der Pumpe mit den Geräteinfos der offiziellen App (`PumpLink.compatSoftwareRevision`). Rechtliche Einschätzung vor Veröffentlichung.
- [ ] **Name/Bundle-ID:** Umbenennung in „iPump-mini“ vorher abschließen (Bundle-ID nicht mehr ändern, sobald Nutzer installiert haben).
- [ ] **Repo öffentlich:** vorher Git-Historie von den Build-Artefakten bereinigen (siehe `docs/tasks.md`).
- [ ] **Datenschutz/Haftung:** Hinweise in App und README (vorhanden), ggf. Prüfung.
