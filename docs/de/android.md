# iPump-mini für Android

*English: [android.md](../en/android.md)*

Die Android-Version liegt in `apps/android/` (Kotlin, Jetpack Compose). Das Protokoll (SAKE, Parser, Allowlist, Nightscout-Mapping) ist eine Kotlin-Portierung von `core/MiniMedKit` und liegt in `core/MiniMedKitKotlin/`. Beide Bibliotheken werden mit denselben Testvektoren geprüft, einschließlich des echten 780G-Handshakes.

> **Status:** Die App baut, alle Tests sind grün, und die Oberfläche läuft im Demo-Modus. **Mit einer echten Pumpe ist sie noch nicht getestet.** Was dabei zu prüfen ist, steht unten unter „Erster Test an der Pumpe“.

## Funktionen (gleich wie iOS)
- Live-Werte, Pumpenstatus, Pumpenhistorie (Boli, Autokorrekturen, Auto-Basal, KH, BZ, Pausen), Graph mit Insulin-Band
- Alarme (Glukose, Pumpenmeldungen, Sensor, „keine Daten“) mit Stummschalten aus der Mitteilung heraus
- Nightscout-Upload, lokale Nightscout-kompatible API auf Port 17580 inklusive `/pebble` und Statusseite
- Deutsch und Englisch, hell/dunkel, mg/dL oder mmol/L, Demo-Modus, Ersteinrichtung mit Nutzungsbedingungen

**Unterschiede zu iOS:**
- Ein **Vordergrunddienst** mit dauerhafter Mitteilung hält die App im Hintergrund am Leben. Die Mitteilung zeigt den aktuellen Wert, ähnlich der Live-Aktivität. Die lokale API antwortet deshalb jederzeit, nicht nur kurz nach jedem Pumpen-Update. Nach einem Neustart des Handys startet der Dienst von selbst.
- Noch **keine Home-Bildschirm-Widgets**.
- Die Sprache stellst du in den Android-Einstellungen der App ein (Android 13+).

## Voraussetzungen
- JDK 17 oder neuer, Android SDK (Plattform 36). Am einfachsten über Android Studio. Ohne Studio: `sdkmanager "platforms;android-36" "build-tools;36.0.0" "platform-tools"` und `apps/android/local.properties` mit `sdk.dir=…`.
- Android-Handy ab **Android 10** mit Bluetooth LE und Peripheral-Modus (das haben praktisch alle aktuellen Geräte).
- `.env` im Repo-Root wie bei iOS (`DEV_MODE`, `TEST_PUMP_SERIAL`) und optional `_vendor/keys/mobile-pump.keydb.hex`. Beides wird nur in **Debug-Builds** übernommen und nie committet.

## Bauen und installieren
```sh
cd apps/android
./gradlew :minimedkit:test          # Protokoll-Bibliothek (Handshake-Test braucht _vendor/keys)
./gradlew :app:testDebugUnitTest    # rendert die Screens mit Demo-Daten (Robolectric)
./gradlew :app:assembleDebug        # app/build/outputs/apk/debug/app-debug.apk
adb install -r app/build/outputs/apk/debug/app-debug.apk
```
Der Debug-Build hat die Paket-ID `de.sgitaize.openminipump.debug` und kann neben einer späteren Release-Version installiert sein. Er nutzt `DEV_MODE` und die Testpumpe aus `.env`.

Protokoll vom Handy holen (Debug-Build):
```sh
adb shell run-as de.sgitaize.openminipump.debug cat files/openminipump.log > openminipump.log
```
Oder in der App: Einstellungen › Info › Protokoll › Teilen.

Screenshots der Screens ohne Gerät: `./gradlew :app:testDebugUnitTest -Pscreenshots=/pfad/zum/ordner`.

## Release-Build und Signaturschlüssel
Release-Builds sind wie bei iOS **öffentlich**: `DEV_MODE=0`, keine `.env`, keine Schlüsseldatenbank (Import in der App). Mit `-PompPublicBuild=0` baust du einen Release-Build für die eigene Pumpe.

Der Signaturschlüssel wird **nie** ins Repo oder in einen Chat kopiert. Wer ihn verliert, kann keine Updates für bereits installierte Apps mehr ausliefern. Deshalb einmalig lokal erzeugen und sicher aufbewahren (Schlüsselbund bzw. Passwortmanager plus Backup):

```sh
keytool -genkeypair -v -keystore ~/.android-keys/ipump-mini-release.jks \
  -alias ipump-mini -keyalg RSA -keysize 4096 -validity 10000
```

Dann `apps/android/keystore.properties` anlegen (gitignored):
```properties
storeFile=/Users/<du>/.android-keys/ipump-mini-release.jks
storePassword=…
keyAlias=ipump-mini
keyPassword=…
```
und bauen: `./gradlew :app:assembleRelease`. Ohne `keystore.properties` entsteht eine unsignierte APK.

## Erster Test an der Pumpe (Simon)
Ablauf wie bei iOS, mit der **Testpumpe** und einem Debug-Build (`DEV_MODE=1`):

1. App installieren und öffnen, Nutzungsbedingungen bestätigen, unter „Berechtigungen“ **Geräte in der Nähe** und **Mitteilungen** erlauben.
2. Einstellungen › Pumpe › **Akku-Optimierung**: iPump-mini auf „Nicht optimieren“ stellen.
3. Eine Kopplung mit iPhone/MiniMed Mobile an der Pumpe entfernen (die Pumpe nimmt nur ein Mobilgerät).
4. In der App **Pumpe koppeln** öffnen. An der Pumpe: Menü › Kopplungsoptionen › Neues Gerät koppeln › „Mobile …“ wählen.
5. Die Android-Kopplungsanfrage bestätigen. Danach sollten Handshake, „Pumpe verifiziert“ und die ersten Werte im Protokoll stehen.
6. Protokoll teilen (oder per `adb` holen), vor allem bei Fehlern.

**Was dabei offen ist** (Laborbuch, 18.10.2026):
- **Name beim Koppeln:** Android kann den Gerätenamen nicht pro Advertisement setzen. „Mobile …“ steht deshalb wie bei JavaPumpConnector und GlycemicGPT in den Medtronic-Herstellerdaten (0x01F9). Zeigt die Pumpe den Namen nicht an, ist das die erste Stelle.
- **Geräteinformationen (DIS 0x0900):** Hersteller und Modell des Handys, „Android“, App-Version `3.3.0(80)` wie auf iOS. Meldet die Pumpe „Gerät nicht kompatibel“, liegt es vermutlich hier.
- **GATT-Client auf der Pumpenverbindung:** Die App öffnet den Client nur, solange die Pumpe mit dem GATT-Server verbunden ist. Android hängt ihn dann an die bestehende Verbindung an, statt eine zweite aufzubauen (die Lehre aus dem iOS-Bug vom 15.10.).
- **Hintergrund über Stunden** mit Doze und Herstellern, die Apps aggressiv beenden.
