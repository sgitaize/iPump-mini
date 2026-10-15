# Translating (German / English)

- **Source language is German:** the German texts in the code are the keys. Translations live in `apps/ios/Shared/Localizable.xcstrings` (app and widgets); system dialogs in `apps/ios/OpenMinipump/InfoPlist.xcstrings`.
- **In-app switch:** Settings › Appearance › Language (System / Deutsch / English). “System” uses German if German comes before English in the iPhone's preferred languages, otherwise English.
  - Technically the app sets `\.locale` at the root (`appPreferences`), so SwiftUI texts follow the choice.
  - Texts built as `String` in code (notifications, status messages, texts from MiniMedKit) go through `L10n.tr("German text", args…)`.
- **SwiftUI rule:** `Text("…")` with a literal is translated, `Text(stringVariable)` is not. For variables use `L10n.tr` or declare the parameter as `LocalizedStringKey`. Numbers and units with `Text(verbatim:)`.

## Adding translations
```sh
cd apps/ios
Scripts/l10n-sync.sh                        # builds and collects all texts into the catalog
python3 Scripts/l10n.py missing > en.json   # missing translations as JSON
# fill in en.json
python3 Scripts/l10n.py apply en.json && rm en.json
```
