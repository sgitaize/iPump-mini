# ADR 0001: Repo liegt außerhalb von iCloud Drive

- Status: angenommen
- Datum: 2026-10-14

## Kontext
Der Projekt-Brief lag ursprünglich in iCloud Drive. Git-Repos in iCloud bekommen häufig kaputte `.git`-Objekte und Konfliktdateien. Außerdem würden `captures/` und `_vendor/` (Gesundheitsdaten, Pairing-Keys, dekompiliertes Material) in die Cloud synchronisiert.

## Entscheidung
Das Repo liegt unter `~/Dev/openMinipump` und ist nicht cloud-synchronisiert. Der ursprüngliche Brief ist als `docs/internal/project-brief.md` im Repo.

## Konsequenzen
Backups von `captures/` und `_vendor/` gibt es nur lokal, z. B. per Time Machine. Diese Ordner dürfen nie in einen Cloud-Ordner kopiert werden.
