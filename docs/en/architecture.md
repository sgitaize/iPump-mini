# Architecture

*How iPump-mini is built, how data flows and where the safety boundaries are.*

## Overview

```
 MiniMed 780G ──BLE──▶ PumpLink ──▶ DataStore ──▶ UI (SwiftUI), widgets, Live Activity
   (central,           (peripheral,      │
    SAKE client)        SAKE server,      ├──▶ AlarmEngine ──▶ local notifications
                        GATT client)      ├──▶ NightscoutUploader ──HTTPS──▶ user's Nightscout
                            │             └──▶ SharedData ──▶ LocalAPIServer (:17580) ──▶ watches
                            ▼
                     ReadOnlyPolicy (every write)
```

Two parts:

| Part | Path | Purpose |
|---|---|---|
| **MiniMedKit** | `core/MiniMedKit` | Swift package without UI: SAKE handshake and session cipher, parsers for the pump's Bluetooth payloads, history timeline, read-only allowlist, Nightscout JSON mapping. Unit-tested (`swift test`), including a replay of a real 780G handshake. |
| **iOS app** | `apps/ios` | SwiftUI app and widget extension (XcodeGen, `project.yml`). Bluetooth, persistence, UI, notifications, local API, Nightscout upload, widgets. |

## Bluetooth roles

The 780G is unusual: **the pump is the Bluetooth central** and connects to the phone, which advertises as a peripheral (`PumpLink`).

1. **Pairing:** the app advertises the SAKE service (`FE82`) with a device name such as "Mobile 123456"; the user selects it on the pump. iOS bonds the link.
2. **SAKE handshake:** the pump (client) and the app (server, `SakeServer`) exchange six 20-byte messages over the SAKE characteristic, using the static keys from the key database. Result: a session cipher (`SeqCrypt`, AES-CTR + truncated AES-CMAC).
3. **Reading:** on the same link the app also acts as **GATT client** and reads the pump's standard services – Insulin Delivery Service (IDS, Medtronic variant) and CGM Service – plus the Device Information Service. Medtronic payloads are encrypted with the session cipher.
4. **Rhythm:** the pump reconnects about every 5 minutes. Each connection wakes the app in the background (CoreBluetooth background modes and state restoration); the app reads status, the latest CGM value and new history records, then iOS suspends it again.
5. **Session persistence:** the session cipher is stored (`SessionStore`), so an app update or relaunch does not need a new handshake.

The app never initiates a connection to the pump itself: an own connection would be unencrypted and makes the pump drop the bond (see `docs/internal/lab-notebook.md`).

## Safety boundaries

- **Read-only (hard rule 1):** every write towards the pump goes through `PumpLink.guardedWrite`, which asks `ReadOnlyPolicy.check`. Allowed are only report/read requests on an explicit allowlist (record access "report" commands, status reader opcodes); everything else is blocked and logged. Reads and subscriptions have their own allowlists (`mayRead`, `maySubscribe`).
- **Pump lock for developer builds (hard rule 2):** `DevModeGuard` – with `DEV_MODE=1` only the serial in `.env` is accepted. Public builds use `DEV_MODE=0`.
- **No proprietary material (hard rule 3):** the SAKE key database is not in the repository or the app. Users load it at runtime from the public OpenMinimed documentation (`KeyImport`, `KeyDatabase.findHex`), checked by CRC and device type; it is stored in the keychain.
- **No secrets in git (hard rule 4):** `.env`, `_vendor/`, `captures/` are ignored; a gitleaks pre-commit hook and GitHub secret scanning run on every push.

## Data flow in the app

| Component | File | Role |
|---|---|---|
| `AppModel` | `App/OpenMinipumpApp.swift` | Composition root; wires everything on `DataStore.onNewReading`. |
| `PumpLink` | `BLE/PumpLink.swift` | Bluetooth peripheral + GATT client, SAKE, read queue, history sync. |
| `DataStore` | `Model/DataStore.swift` | Readings, pump snapshot, treatments, IOB history; JSON file in the app container; `SharedData` copy for the server thread. |
| `AlarmEngine` | `Alarms/AlarmEngine.swift` | Glucose and pump alarms as local notifications (time-sensitive for urgent ones), snooze, presets. |
| `Watchdog` | `App/Watchdog.swift` | Dead man's switch notification when no data arrives (app closed, pump out of range). |
| `NightscoutUploader` | `Nightscout/NightscoutUploader.swift` | Optional upload of entries, devicestatus and treatments to the user's Nightscout; immediately on each new value. |
| `LocalAPIServer` | `API/LocalAPIServer.swift` | Nightscout-compatible HTTP server on port 17580 (loopback by default, Wi-Fi with secret). In the background reachable ~25 s after each pump update; `/pebble` reports the wake schedule (`ompSync`). |
| `WidgetBridge` | `App/WidgetBridge.swift` | Writes the widget snapshot (App Group), reloads widgets within their budget, updates the Live Activity. |
| `PebbleMonitor` | `App/PebbleMonitor.swift` | Optional notification when a watch face stops fetching. |
| `DemoMode` | `App/DemoMode.swift` | Simulated data without Bluetooth for review and trying the app. |
| Widgets | `Widgets/`, `Shared/` | WidgetKit timeline provider, widget and Live Activity views, shared settings and localisation (`L10n`). |

## Background behaviour (iOS limits)

- The app runs only while handling a Bluetooth event of the pump (about every 5 minutes) and for a short background task afterwards. Nightscout upload, alarms, widgets and the Live Activity are updated in that window.
- The local API is therefore reachable only briefly in the background; clients should poll at `ompSync.nextWake` (see [api.md](api.md)).
- Home Screen widgets have a daily reload budget (~40–70); the app spends it on relevant changes. The Live Activity has no such budget.
- If the user swipes the app away, iOS does not wake it any more; the watchdog notification asks to reopen it.

## Localisation and settings

German is the source language; English translations are in `Shared/Localizable.xcstrings` ([translating.md](translating.md)). Appearance, language, unit and target range are shared with the widgets through the App Group (`Prefs`).

## Build variants

| Variant | How | Key database | Pump lock |
|---|---|---|---|
| Developer | Xcode / `xcodebuild` with `.env` | embedded from `_vendor/keys` if present | `DEV_MODE=1`, serial from `.env` |
| Public (AltStore, TestFlight) | `OMP_PUBLIC_BUILD=1 OMP_PUBLIC_DEV_MODE=0` (release workflow) | loaded by the user at runtime | none (any paired 780G) |

## Tests

`cd core/MiniMedKit && swift test` – SAKE (including a captured handshake), parsers, history timeline, treatment classification, read-only policy, Nightscout/pebble mapping, key database extraction. App-level behaviour is verified on the device and in the simulator (demo mode, widget gallery).
