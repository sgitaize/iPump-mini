# Build iPump-mini yourself

*Deutsch: [setup-ios.md](setup-ios.md)*

You need a Mac with **Xcode**, an **iPhone** with iOS 17+ and an **Apple ID**. The free personal team is enough; the app then has to be reinstalled every 7 days.

## 1. Tools and source
```sh
brew install xcodegen gitleaks
git clone https://github.com/sgitaize/iPump-mini.git
cd iPump-mini
git config core.hooksPath .githooks   # secret scan before every commit (needs gitleaks)
```

## 2. Pump lock (`.env`)
Copy `.env.example` to `.env`. Developer builds are locked to one pump:
```sh
DEV_MODE=1
TEST_PUMP_SERIAL=NG1234567X   # serial number of YOUR pump (back of the pump)
```
Without `.env` the app rejects every pump.

## 3. Signing
```sh
cp apps/ios/Config/Local.xcconfig.example apps/ios/Config/Local.xcconfig
```
In `Local.xcconfig`:
- `DEVELOPMENT_TEAM` – your team ID (Xcode › Settings › Accounts › your team).
- `OMP_BUNDLE_ID` – with a free team, an ID unique to you, e.g. `de.yourname.ipumpmini`.
- Capabilities: the default uses an **App Group** (widgets), which free teams support. With a paid team you can add time-sensitive notifications: `OMP_APP_ENTITLEMENTS = OpenMinipump/OpenMinipump-paid.entitlements`.

## 4. Build and run
```sh
cd apps/ios
xcodegen                     # generates OpenMinipump.xcodeproj
open OpenMinipump.xcodeproj
```
Choose your iPhone and press **⌘R**. The first run with a new capability must be started from Xcode so it can create the provisioning profile; later builds also work from the command line:
```sh
xcodebuild -project OpenMinipump.xcodeproj -scheme OpenMinipump -destination 'id=<UDID>' -allowProvisioningUpdates build
xcrun devicectl device install app --device <UDID> <DerivedData>/Build/Products/Debug-iphoneos/OpenMinipump.app
```
Enable Developer Mode on the iPhone (Settings › Privacy & Security) and trust the developer profile (Settings › General › VPN & Device Management).

## 5. Key database
On first start the app offers to load the SAKE key database from the public [OpenMinimed documentation](https://github.com/OpenMinimed/Documentation/blob/main/key_databases.md). Alternatively, put the hex line into `_vendor/keys/mobile-pump.keydb.hex` (gitignored) and it is embedded into your own build.

## 6. Tests
```sh
cd core/MiniMedKit && swift test
```
The SAKE tests replay a real 780G handshake; they are skipped if the key database is not in `_vendor/keys/`.

## Notes
- The generated Xcode project is not committed; edit `apps/ios/project.yml` instead.
- Translations: [localization.md](localization.md). Local API: [api.md](api.md).
- Never commit `.env`, `_vendor/`, `captures/` or keys – they are gitignored on purpose.
