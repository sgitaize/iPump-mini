# iPump-mini for Android

*Deutsch: [android.md](../de/android.md)*

The Android version lives in `apps/android/` (Kotlin, Jetpack Compose). The protocol layer (SAKE, parsers, read-only allowlist, Nightscout mapping) is a Kotlin port of `core/MiniMedKit` in `core/MiniMedKitKotlin/`. Both libraries are tested with the same vectors, including the captured 780G handshake.

> **Status:** builds, all tests pass, the UI runs in demo mode. **Not yet tested against a real pump.** See the German page for the first hardware test and the open questions.

## Build
```sh
cd apps/android
./gradlew :minimedkit:test          # protocol library (handshake test needs _vendor/keys)
./gradlew :app:testDebugUnitTest    # renders the screens with demo data (Robolectric)
./gradlew :app:assembleDebug        # app/build/outputs/apk/debug/app-debug.apk
adb install -r app/build/outputs/apk/debug/app-debug.apk
```
Requirements: JDK 17+, Android SDK platform 36, a phone with Android 10+ and BLE peripheral support. Debug builds take `DEV_MODE`/`TEST_PUMP_SERIAL` from `<repo>/.env` and the key database from `_vendor/keys/` (both gitignored). Release builds are public builds (`DEV_MODE=0`, no key database; users import it in the app).

## Signing
Create the release keystore once on your own machine and keep it safe (password manager + backup). It never goes into the repository:
```sh
keytool -genkeypair -v -keystore ~/.android-keys/ipump-mini-release.jks -alias ipump-mini -keyalg RSA -keysize 4096 -validity 10000
```
Reference it from the gitignored `apps/android/keystore.properties` (`storeFile`, `storePassword`, `keyAlias`, `keyPassword`) and run `./gradlew :app:assembleRelease`. Add `-PompGithubApk=1` for the APK on GitHub: only that variant points to newer GitHub releases. The Google Play bundle (`./gradlew :app:bundleRelease`) is built without it.

## Differences from iOS
- A foreground service with a permanent notification keeps the app reachable for the pump; the notification shows the current value. The local API therefore answers at any time.
- **Home screen widget** “Glucose” (value, trend, age), but no lock screen widgets and no Live Activity. The permanent notification takes over that role.
- Language is chosen in the app's Android settings (Android 13+).
