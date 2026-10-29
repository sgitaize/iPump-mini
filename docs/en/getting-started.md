# iPump-mini – Getting started

*Deutsch: [erste-schritte.md](../de/erste-schritte.md)*

> **Important:** iPump-mini is not a medical device and is not meant for treatment decisions. The pump's displays and alarms are always authoritative. Keep the pump's alarms turned on. You have to accept the terms of use on first launch.

Setup takes about 10 minutes. Keep the pump and phone close together and make sure you have internet access (for the key database).

## What you need
- **iPhone** with iOS 17 or later **or an Android phone** with Android 10 or later
- MiniMed 780G (tested with firmware 6.23W) with Simplera Sync or Guardian 4
- The Android version is a **beta** and has not been tested with a real pump yet.

## Overview
1. Install the app
2. Unpair MiniMed Mobile on the pump
3. Delete the old Bluetooth pairing on the phone
4. Launch the app, terms of use
5. Load the key database from OpenMinimed
6. Allow permissions
7. Choose the sensor
8. Pair the pump
9. Check that values arrive

## 1. Install the app
- **iPhone:** from the App Store. Or build it yourself, see [Building](building.md).
- **Android:** On the [releases page](https://github.com/sgitaize/iPump-mini/releases), download `ipump-mini.apk` from the newest Android release on your phone and open it. Android asks whether your browser or files app may install apps: allow it once, then tap “Install”. If you still have the first beta (`de.sgitaize.openminipump`), uninstall it first.

## 2. Unpair MiniMed Mobile on the pump
The pump accepts only **one** mobile device. If MiniMed Mobile (or another app) is paired, that pairing has to go first.

1. On the pump: **Menu › Pairing options › Paired devices**.
2. Select the phone or “MiniMed Mobile” › **Unpair** › confirm.

Unpair only the mobile device, **not the sensor**. Labels may differ slightly depending on the software version. Afterwards MiniMed Mobile no longer uploads to CareLink.

## 3. Delete the old Bluetooth pairing on the phone
If the phone was paired with the pump before, it still remembers it, which gets in the way of the new pairing.

- **Android:** Settings › Connected devices (Samsung: Connections › Bluetooth) › gear next to the pump › **Unpair/Forget**.
- **iPhone:** Settings › Bluetooth › ⓘ next to the pump › **Forget This Device**.
- **Close or uninstall MiniMed Mobile** so it does not take the connection back.

If the pump is not in the list, there is nothing to do.

## 4. Launch the app, terms of use
On first launch you accept the terms of use. You can read them later under Settings › Info. To look around first, choose **demo mode** (simulated values, no Bluetooth).

## 5. Load the key database
The app needs the SAKE key database “Mobile Application ↔ Insulin Pump” for the encrypted connection. It is **not** part of the app but is loaded from the public documentation of the [OpenMinimed](https://github.com/OpenMinimed) project.

- During setup or under Settings › Pump › Key database, tap **“Load from OpenMinimed”**. The app loads [key_databases.md](https://github.com/OpenMinimed/Documentation/blob/main/key_databases.md) and takes the matching block. Checksum and device type are verified.
- Alternatively: enter your own address or paste the hex block.

## 6. Allow permissions
- **Android:** allow “Nearby devices” (Bluetooth) and notifications. Under Settings › Pump › Battery optimisation, choose **“Don't optimise”** for iPump-mini, otherwise Android restricts the app in the background.
- **iPhone:** allow Bluetooth and notifications.

Without notifications there are no alarms. Pitfalls are listed below under “Alarms”.

## 7. Choose the sensor
Simplera Sync (no transmitter) or Guardian 4 (with transmitter). This decides which values are shown. You can change it later under Settings › Sensor.

## 8. Pair the pump
1. Open **“Pair pump”** in the app. It shows its name, e.g. **“Mobile 123456”**. Keep the app in the foreground and the phone unlocked.
2. On the pump: **Menu › Pairing options › Pair new device**.
3. The pump searches and shows “Mobile …” with the name from the app. Select it and confirm.
4. A **Bluetooth pairing request** appears on the phone: tap “Pair”.
5. The pump reports that pairing succeeded.

If it fails: check steps 2 and 3 (old pairing really removed on pump and phone?), turn Bluetooth on the phone off and on, and start again.

## 9. Check that values arrive
The current value and the pump status appear shortly. The history of the last hours is loaded afterwards. From then on the pump checks in about every 5 minutes by itself. Compare the first values with the pump's display.

## Everyday use
- **Don't swipe the app away.**
  - **iPhone:** The pump wakes the app every 5 minutes. That only works while it is running in the background. If it was closed, a notification reminds you.
  - **Android:** A service with a permanent notification keeps the app reachable. The notification shows the current value. The service starts by itself after a phone restart.
- **Keep Bluetooth on.** After turning it back on, the pump reconnects by itself.
- **No connection?** Bring the pump in range and open the app. If that does not help after a few minutes, turn Bluetooth off and on. Only if that fails too, pair again (from step 2).
- **Daylight saving time:** The app detects when the pump clock was changed (e.g. summer/winter time) and corrects the value times by itself.
- **Widgets (iPhone):** long-press the home or lock screen › Edit › Add widget › iPump-mini. Appearance under Settings › Widgets.
- **Live Activity / Dynamic Island (iPhone):** starts when you open the app. iOS ends it after 8 hours.
- **Appearance:** light/dark/system, unit (mg/dL or mmol/L) and target range under Settings › Appearance. Language: iPhone in the app, Android in the app's Android settings.
- **Nightscout (optional):** URL and API secret under Settings › Nightscout. New values are uploaded right away, along with pump status and treatments.
- **Local API (optional):** Nightscout-compatible on port 17580, e.g. for Pebble watch faces, see [api.md](api.md).

## Alarms
- **Pump alarms:** The app passes on pump messages. Acknowledge them on the pump.
- **Testing:** Under Settings › Alarms, tap “Send test alarm”, lock the phone and check that the alarm arrives with sound.
- **Android – Do Not Disturb:** In the notification channel “Urgent alarms”, turn on “Override Do Not Disturb”, or add iPump-mini as an exception.
- **iPhone – Focus/Sleep:** A Focus holds back normal notifications. Add iPump-mini under “Allowed apps” in the Focus, otherwise alarms stay silent at night.
- **iPhone – silent switch:** With the iPhone muted, alarms arrive without sound. Only “critical alerts” get through, which require Apple's approval that self-built versions don't have.

The app contains a short version of this guide under Settings › Info › Guide.
