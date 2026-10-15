# iPump-mini – Get started

*Deutsch: [erste-schritte.md](../de/erste-schritte.md)*

> **Important:** iPump-mini is not a medical device and not intended for treatment decisions. The pump's displays and alarms are always authoritative; keep the pump's alarms turned on. You have to accept the terms of use on first start.

## What you need
- An iPhone with iOS 17 or later
- A MiniMed 780G (tested with firmware 6.23W) with Simplera Sync or Guardian 4
- To install: AltStore/SideStore (once released) or a Mac with Xcode ([build it yourself](building.md))

## 1. Install and accept the terms
On first start you pick the language (German/English, default: like the iPhone) and accept the terms of use. You can read them again later under Settings › Info.

## 2. Load the key database
For the encrypted connection the app needs the SAKE key database “Mobile Application ↔ Insulin Pump”. It is **not** included in the app.

- In the setup, or under Settings › Pump › Key database, tap **“Load from OpenMinimed”**. The app downloads the public page [key_databases.md](https://github.com/OpenMinimed/Documentation/blob/main/key_databases.md) and takes the matching block. Checksum and device type are verified.
- Alternatively, enter another address or paste the hex block.

## 3. Allow notifications
Without permission there are no alarms. Tap “Allow notifications” in the setup.

**Pitfalls:**
- **Focus / Sleep:** a Focus holds back normal notifications. Add iPump-mini to the Focus under “Allowed apps”, otherwise alarms stay silent at night.
- **Silent switch:** with the iPhone silenced, alarms come without sound. Only “critical alerts” break through; they need an approval from Apple that self-built and AltStore versions don't have.
- **Time sensitive:** only available with a paid developer account. With a free Apple ID, alarms arrive as normal notifications.
- **Pump alerts:** the app forwards the pump's alerts; you clear them on the pump.

## 4. Choose your sensor
Simplera Sync (no transmitter) or Guardian 4 (with transmitter). This decides which values are shown.

## 5. Pair the pump
1. The pump accepts only **one** mobile device. If MiniMed Mobile is paired, remove that pairing on the pump first.
2. Open “Pair pump” in the app. Keep the app in the foreground and the iPhone unlocked.
3. On the pump: Menu › Pairing options › Pair new device. Select “Mobile …” (the name shown in the app) and confirm.
4. Confirm the Bluetooth pairing request on the iPhone.
5. The first values appear shortly afterwards.

## 6. Day to day
- **Don't swipe the app away.** The pump wakes the app every 5 minutes; this only works while it runs in the background. If it was closed, a notification reminds you.
- **No connection?** Pump in range, open the app. If that doesn't help after a few minutes, turn Bluetooth off and on in iPhone Settings. Only then pair again.
- **Widgets:** long-press the Home or Lock Screen › Edit › Add widget › iPump-mini. Appearance under Settings › Widgets.
- **Live Activity / Dynamic Island:** starts when you open the app; iOS ends it after 8 hours.
- **Appearance:** light/dark/system, language, unit (mg/dL or mmol/L) and target range under Settings › Appearance.
- **Nightscout (optional):** URL and API secret under Settings › Nightscout. New values are uploaded immediately, plus pump status and treatments.
- **Local API (optional):** Nightscout-compatible on port 17580, see [api.md](api.md).

The app contains the same guide under Settings › Info › Guide.
