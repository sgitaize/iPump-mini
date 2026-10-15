# Sprachen (Deutsch / Englisch)

- **Quellsprache Deutsch:** Die deutschen Texte im Code sind die Schlüssel. Übersetzungen stehen in `apps/ios/Shared/Localizable.xcstrings` (App und Widgets), Systemdialoge in `apps/ios/OpenMinipump/InfoPlist.xcstrings`.
- **Umschalter in der App:** Einstellungen › Aussehen › Sprache (Wie System / Deutsch / English). „Wie System“ nimmt Deutsch, wenn Deutsch vor Englisch in den bevorzugten Sprachen des iPhones steht, sonst Englisch.
  - Technisch setzt die App `\.locale` an der Wurzel (`appPreferences`), damit SwiftUI-Texte der Auswahl folgen.
  - Texte, die im Code als `String` entstehen (Mitteilungen, Statusmeldungen, Texte aus MiniMedKit), laufen über `L10n.tr("Deutscher Text", args…)`.
- **SwiftUI-Regel:** `Text("…")` mit einem Literal wird übersetzt, `Text(stringVariable)` nicht. Für Variablen `L10n.tr` nutzen oder den Parameter als `LocalizedStringKey` deklarieren. Zahlen und Einheiten mit `Text(verbatim:)`.

## Neue Texte übersetzen
```sh
cd apps/ios
Scripts/l10n-sync.sh                        # baut, übernimmt alle Texte in den Katalog
python3 Scripts/l10n.py missing > en.json   # fehlende Übersetzungen als JSON
# en.json ausfüllen
python3 Scripts/l10n.py apply en.json && rm en.json
```
