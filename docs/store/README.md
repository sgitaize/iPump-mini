# Store material

| What | Where |
|---|---|
| Texts as uploaded (per locale, app, review) | [metadata/](metadata/) |
| Background, review answers, TestFlight, AltStore | [../internal/store-application.md](../internal/store-application.md) |
| Screenshots 6.9″ (1320 × 2868), German | [screenshots/de/](screenshots/de/) |
| Screenshots 6.9″ (1320 × 2868), English | [screenshots/en/](screenshots/en/) |
| Header artwork (optional, „Kopfzeile“) 3840 × 1646 and 5244 × 2950, DE/EN | [header/](header/) (`render-header.swift`) |
| App icon 1024 × 1024 (no alpha) | [../../apps/ios/OpenMinipump/Assets.xcassets/AppIcon.appiconset/AppIcon.png](../../apps/ios/OpenMinipump/Assets.xcassets/AppIcon.appiconset/AppIcon.png) |
| Privacy policy | https://simongutjahr.de/impressum/#ipump-mini |
| Marketing page | https://simongutjahr.de/dev/ipump-mini/ |
| Support | https://github.com/sgitaize/iPump-mini/issues |

Screenshots (all with simulated demo data, iPhone 18 Pro Max simulator, public build):

1. `01-home` – current value, graph with treatments, tapped value with details
2. `02-home-dark` – dark mode
3. `03-widgets` – Live Activity (awake and Always-On), Home and Lock Screen widgets
4. `04-alarms` – alarm presets and thresholds
5. `05-settings` – settings
6. `06-onboarding` – first start

Regenerate: `apps/ios` → build with `OMP_PUBLIC_BUILD=1 OMP_PUBLIC_DEV_MODE=0` for the simulator, launch with `-demoData -screenshot -sensorType simplera -appLanguage de|en` plus `-selectPoint`, `-widgetGallery`, `-screen alarms|settings|guide|terms|about` or `-onboarding`; status bar via `xcrun simctl status_bar … override --time 9:41`.

## Upload to App Store Connect
`apps/ios/Scripts/asc_metadata.py` uploads texts, category, review details and screenshots via the App Store Connect API (key in `~/.appstoreconnect/`, never in git). App Privacy, pricing/availability and the age rating are set by hand.
