# iPump-mini – Texte für Veröffentlichung und Anträge

Stand 15.10.2026. Vorlagen zum Kopieren für App Store Connect, TestFlight, AltStore (Classic und PAL) und den Antrag auf kritische Alarme. Apple-Felder auf Englisch, Store-Texte zusätzlich auf Deutsch. Keine Rechtsberatung.

---

## 1. Kern-Botschaft (für alle Kanäle gleich)

**Was ist iPump-mini?**
Eine private, kostenlose Open-Source-App, mit der Menschen mit einer MiniMed-780G-Insulinpumpe die Daten **ihrer eigenen Pumpe** direkt auf dem iPhone sehen: Sensorglukose mit Trend, aktives Insulin, Reservoir, SmartGuard-Status und die Abgabehistorie. Die App spricht per Bluetooth direkt mit der Pumpe, ohne Hersteller-Cloud.

**Warum braucht man das?**
- Die Daten der 780G sind auf dem iPhone sonst nur über die App des Herstellers und dessen Cloud zugänglich. Es gibt keinen lokalen Zugriff, keine offene Schnittstelle und keine Anbindung an eigene Werkzeuge.
- Nutzer*innen wollen ihre Werte dort sehen, wo sie sie brauchen: auf dem Sperrbildschirm, in der Dynamic Island, auf einer Smartwatch (z. B. Pebble), in ihrem eigenen Nightscout für Angehörige, auch ohne Internet.
- Der EU Data Act gibt Nutzer*innen vernetzter Geräte ein Recht auf die Daten, die ihr Gerät erzeugt. iPump-mini ist ein Werkzeug, dieses Recht für die eigene Pumpe praktisch auszuüben.

**Was ist das Ziel?**
Transparenz und Selbstbestimmung über die eigenen Gesundheitsdaten, lokal und datensparsam. Keine Konkurrenz zur Hersteller-App und kein Ersatz für die Pumpe.

**Was die App ausdrücklich nicht ist und nicht tut:**
- **Kein Medizinprodukt**, keine Zulassung, keine CE-Kennzeichnung.
- **Keine Therapieentscheidungen.** Die App dient der Information und dem Komfort. Insulin dosieren, Unterzuckerungen behandeln und alle anderen Behandlungsentscheidungen richten sich nach den Anzeigen und Alarmen der Pumpe und den Vorgaben des Diabetes-Teams.
- **Nur lesend, technisch erzwungen.** Die App kann keinen Bolus abgeben, keine Einstellungen ändern und keine Alarme quittieren. Jeder Zugriff auf die Pumpe läuft über eine Allowlist reiner Abfragen (`ReadOnlyPolicy.swift`); alles andere wird blockiert und protokolliert.
- **Die Alarme der Pumpe bleiben maßgeblich.** Alarme der App sind eine zusätzliche, unverbindliche Erinnerung.
- **Jede Insulinabgabe läuft über die Pumpe selbst – und dort steht der Wert.** Wer einen Bolus abgeben will, muss die Pumpe in die Hand nehmen und am Gerät bedienen. Dabei sieht man zwangsläufig den aktuellen Sensorwert auf dem Display der Pumpe, bevor Insulin abgegeben wird. Ein falscher oder veralteter Wert in iPump-mini kann deshalb nicht unbemerkt zu einer Dosis führen: Die maßgebliche Anzeige liegt im Behandlungsablauf immer dazwischen. Das begrenzt das Risiko der App strukturell, nicht nur durch Hinweise.
- **Keine Datensammlung.** Daten bleiben auf dem iPhone. Die Entwickler erhalten nichts. Optional lädt die App in einen eigenen Nightscout-Server der Nutzer*innen hoch.
- **Keine Verbindung zu Medtronic.** Medtronic, MiniMed, SmartGuard, Guardian, Simplera und CareLink sind Marken ihrer Inhaber.
- Beim ersten Start müssen Nutzer*innen den **Nutzungsbedingungen** zustimmen und bestätigen, dass die Pumpe für Behandlungsentscheidungen und Alarme maßgeblich ist.

---

## 2. App Store Connect

### Name und Untertitel
| Feld | EN | DE |
|---|---|---|
| Name (30) | iPump-mini | iPump-mini |
| Subtitle (30) | Read-only view of your pump | Deine Pumpe, nur lesend |

> Hinweis: Den Markennamen „MiniMed“ nicht in Name/Untertitel verwenden (Markenrecht, Richtlinie 5.2). In der Beschreibung nur beschreibend („compatible with …“).

### Promotional Text (170)
- **EN:** See your own MiniMed 780G on your iPhone – glucose, active insulin, history, widgets and Dynamic Island. Read-only, local, open source. Not for treatment decisions.
- **DE:** Deine MiniMed 780G auf dem iPhone – Glukose, aktives Insulin, Historie, Widgets und Dynamic Island. Nur lesend, lokal, Open Source. Nicht für Therapieentscheidungen.

### Description (EN)
```
iPump-mini shows the data of your own MiniMed 780G insulin pump on your iPhone – directly over Bluetooth, without a cloud.

WHAT YOU SEE
• Sensor glucose with trend arrow and change, every 5 minutes, also in the background
• Active insulin, reservoir, pump battery, SmartGuard state, basal rate, time in range
• Pump history: boluses, SmartGuard auto corrections, carbs, BG checks, calibrations
• Graph up to 24 hours – tap or slide for details
• Widgets for Home and Lock Screen, Live Activity and Dynamic Island
• Optional reminders for low/high values and pump alerts
• Optional upload to your own Nightscout, and a local Nightscout-compatible interface for watches
• German and English, light and dark mode, mg/dL or mmol/L

READ-ONLY BY DESIGN
iPump-mini only reads. It cannot deliver insulin, change settings or clear alarms. Every request to the pump goes through an allowlist of read queries; everything else is blocked.

IMPORTANT
iPump-mini is not a medical device and must not be used for treatment decisions. Values may be late, wrong or missing. Your pump's displays and alarms are always authoritative – keep them turned on. The app's reminders are an additional, non-binding convenience.

PRIVACY
Your data stays on your iPhone. The developer receives no data. Nothing is sent anywhere unless you set up your own Nightscout server.

REQUIREMENTS
A MiniMed 780G insulin pump with Simplera Sync or Guardian 4 sensor. The pump accepts one mobile device; pairing iPump-mini replaces a pairing with another app.

Open source (GPL-3.0): github.com/sgitaize/iPump-mini
Not affiliated with or endorsed by Medtronic. MiniMed, SmartGuard, Guardian, Simplera and CareLink are trademarks of their respective owners.
```

### Beschreibung (DE)
```
iPump-mini zeigt die Daten deiner eigenen Insulinpumpe MiniMed 780G auf dem iPhone – direkt per Bluetooth, ohne Cloud.

WAS DU SIEHST
• Sensorglukose mit Trendpfeil und Änderung, alle 5 Minuten, auch im Hintergrund
• Aktives Insulin, Reservoir, Pumpenbatterie, SmartGuard-Status, Basalrate, Zeit im Zielbereich
• Pumpenhistorie: Boli, SmartGuard-Autokorrekturen, Kohlenhydrate, BZ-Messungen, Kalibrierungen
• Verlauf bis 24 Stunden – antippen oder wischen für Details
• Widgets für Home- und Sperrbildschirm, Live-Aktivität und Dynamic Island
• Optionale Erinnerungen bei niedrigen/hohen Werten und Pumpenmeldungen
• Optionaler Upload in dein eigenes Nightscout und eine lokale, Nightscout-kompatible Schnittstelle für Uhren
• Deutsch und Englisch, hell und dunkel, mg/dL oder mmol/L

NUR LESEND
iPump-mini liest ausschließlich. Die App kann kein Insulin abgeben, keine Einstellungen ändern und keine Alarme quittieren. Jede Anfrage an die Pumpe läuft über eine Liste erlaubter Abfragen; alles andere wird blockiert.

WICHTIG
iPump-mini ist kein Medizinprodukt und darf nicht für Therapieentscheidungen verwendet werden. Werte können verspätet, falsch oder unvollständig sein. Maßgeblich sind immer die Anzeigen und Alarme deiner Pumpe – lass sie eingeschaltet. Die Erinnerungen der App sind eine zusätzliche, unverbindliche Hilfe.

DATENSCHUTZ
Deine Daten bleiben auf deinem iPhone. Der Entwickler erhält keine Daten. Es wird nichts gesendet, außer du richtest dein eigenes Nightscout ein.

VORAUSSETZUNGEN
Eine Insulinpumpe MiniMed 780G mit Sensor Simplera Sync oder Guardian 4. Die Pumpe nimmt ein Mobilgerät an; die Kopplung mit iPump-mini ersetzt die Kopplung mit einer anderen App.

Open Source (GPL-3.0): github.com/sgitaize/iPump-mini
Keine Verbindung zu Medtronic. MiniMed, SmartGuard, Guardian, Simplera und CareLink sind Marken ihrer Inhaber.
```

### Keywords (100)
- **EN:** `diabetes,insulin pump,cgm,glucose,nightscout,widget,smartguard,780g,type 1,open source`
- **DE:** `diabetes,insulinpumpe,cgm,glukose,zucker,nightscout,widget,780g,typ 1,open source`

### Weitere Felder
| Feld | Wert |
|---|---|
| Category | Medical (ehrlich; strengere Prüfung) – Alternative Health & Fitness |
| Support URL | https://github.com/sgitaize/iPump-mini/issues |
| Marketing URL | https://simongutjahr.de/dev/ipump-mini/ |
| Privacy Policy URL | https://simongutjahr.de/impressum/#ipump-mini (live seit 15.10.2026, DE/EN) |
| Price | Free |
| App Privacy („Nutrition Label“) | Data Not Collected |
| Age Rating | 4+ (keine medizinischen Ratschläge im Sinne der Altersfreigabe; „Medical/Treatment Information: None“ prüfen) |
| Copyright | 2026 Simon Gutjahr |
| Export compliance | Siehe Abschnitt 9. |

### App Review Information – Notes (EN)
```
Thank you for reviewing iPump-mini.

PURPOSE
iPump-mini lets people who use a MiniMed 780G insulin pump view the data of their own pump on their iPhone. The pump otherwise only shares data through the manufacturer's app and cloud. iPump-mini reads the data locally over Bluetooth LE, without any server.

READ-ONLY / SAFETY
- Every insulin delivery is made on the pump itself. To give a bolus, the user has to pick up the pump and operate it; the pump's display shows the current sensor glucose at that moment. A wrong or outdated value in iPump-mini can therefore never lead to a dose unnoticed – the authoritative reading on the pump is always part of the treatment step.
- The app only reads. It cannot deliver insulin, change pump settings or clear alarms. All requests to the pump pass through a hard-coded allowlist of read-only report requests (source: core/MiniMedKit/Sources/MiniMedKit/Safety/ReadOnlyPolicy.swift in the public repository); anything else is blocked and logged.
- The app is not a medical device and is not intended for treatment decisions. This is stated in the description, in the app (footer on the main screen, About page) and in terms of use that every user must accept on first launch, including an explicit confirmation that the pump's displays and alarms are authoritative.
- Optional notifications are labelled as additional, non-binding reminders; the pump's own alarms stay on.

PRIVACY
No account, no analytics, no data collection. Data stays on the device. An optional upload goes only to a Nightscout server the user operates.

HOW TO REVIEW WITHOUT A PUMP
The app requires a MiniMed 780G pump. For review, a demo mode with simulated values is available: on the first screen tap "Try without a pump (demo)", accept the terms, and the app shows simulated values (a new one every 5 minutes). It can also be switched on under Settings › Info › Demo mode. Demo mode does not use Bluetooth, saves nothing, uploads nothing and gives no alarms; widgets and the Live Activity show the simulated values.

BLUETOOTH (UIBackgroundModes bluetooth-central + bluetooth-peripheral)
The pump connects to the phone: the app runs a GATT server via CBPeripheralManager (advertising for pairing/reconnect; the pump writes/subscribes) and, over the same link, reads the pump's GATT services (IDS, CGM, Battery) via CBCentralManager. New values arrive every 5 minutes, also in the background/lock screen (widgets, Live Activity). A screen recording on a physical iPhone with a pump is attached. Demo mode uses no Bluetooth, so this is not visible without a pump.

INTEROPERABILITY
The app is an independent, open-source implementation (GPL-3.0) for interoperability with the user's own device. It contains no code or assets of the manufacturer. Source: https://github.com/sgitaize/iPump-mini

Contact: kontakt@simongutjahr.de
```

### What's New (erste Version)
- **EN:** First release. Live values, pump history, graph with details, widgets, Live Activity, optional reminders, Nightscout upload, local API, German and English.
- **DE:** Erste Version. Live-Werte, Pumpenhistorie, Verlauf mit Details, Widgets, Live-Aktivität, optionale Erinnerungen, Nightscout-Upload, lokale API, Deutsch und Englisch.

---

## 3. TestFlight

**Beta App Description (EN):**
```
iPump-mini shows the data of your own MiniMed 780G insulin pump on your iPhone, read-only, over Bluetooth. Not a medical device, not for treatment decisions – the pump's displays and alarms are authoritative.
```
**What to Test (EN):**
```
- Pairing with the pump (remove an existing MiniMed Mobile pairing first)
- Values arriving every 5 minutes in the background
- Widgets, Live Activity and notifications
- Optional: Nightscout upload
Please report problems with the log (Settings › Info › Log › Share).
```
**Feedback-E-Mail:** kontakt@simongutjahr.de

---

## 4. Kritische Alarme – zurückgestellt

Simon (15.10.2026): vorerst **keine** kritischen Alarme beantragen. Dringende Alarme sind zeitkritische Mitteilungen; die App erklärt unter Einstellungen › Alarme › „So richtest du es ein“, wie man sie einschaltet und im Fokus erlaubt. Der Antragstext liegt in der Git-Historie dieser Datei, falls er später gebraucht wird.

---

## 5. AltStore Classic (Quelle `altstore/source.json`)

- **Subtitle:** Reads the MiniMed 780G via Bluetooth – read-only.
- **Beschreibung:** wie App-Store-Beschreibung (EN), Absatz „REQUIREMENTS“ ergänzen um: „Installed via AltStore with your own Apple ID: refresh every 7 days, max. 3 sideloaded apps. On first start the app loads the SAKE key database from the public OpenMinimed documentation.“
- **Release Notes je Version:** kurz, auf Englisch.

## 6. AltStore PAL (EU, Notarisierung durch Apple)

Für die Notarisierung in App Store Connect („Notarization“ statt „App Review“) dieselben Notes wie in Abschnitt 2 verwenden. Zusätzlich:
```
Distribution: alternative app marketplace (AltStore PAL) in the EU. The app is free and has no in-app purchases.
```
Prüfpunkte der Notarisierung sind Funktion, Sicherheit und Datenschutz (Teilmenge der Richtlinien). Ob eine App ohne Medizinprodukt-Zulassung mit Glukosewerten durchgeht, ist offen.

---

## 7. Häufige Rückfragen (Antwort-Bausteine, EN)

**„Does your app require regulatory clearance (Guideline 1.4.1)?“**
```
iPump-mini does not diagnose, treat or dose. It displays data that the user's own, already approved pump has measured and calculated, for information and convenience. It explicitly instructs users not to use it for treatment decisions and to rely on the pump's displays and alarms, and requires users to confirm this before first use. It cannot control the pump in any way.
```
Additional argument (structural risk control):
```
Treatment always happens on the pump. iPump-mini cannot deliver or suggest a dose, and to deliver insulin the user must operate the pump, whose display shows the current sensor glucose at that moment. The pump's own reading is therefore always in front of the user before any insulin is given; iPump-mini only adds visibility (lock screen, watch, caregivers via the user's own Nightscout).
```

**„Do you have permission to use the manufacturer's protocol / trademarks?“**
```
The app is an independent implementation for interoperability with the user's own device, based on public research (OpenMinimed, GPL-3.0) and the public Bluetooth SIG specifications (Insulin Delivery Service, CGM Service). It contains no code or assets of the manufacturer. Trademarks are used only descriptively to state compatibility, with a clear non-affiliation notice.
```
**„Guideline 2.5.4 – bluetooth-central/-peripheral in UIBackgroundModes, no BLE functionality found“** (16.10.2026, Build 1.0.1 (3), Prüfgerät iPad Air ohne Pumpe → nur Demo-Modus gesehen). Beide Modi werden gebraucht, nicht entfernen. Antwort + Bildschirmaufnahme vom iPhone mit echter Pumpe:
```
Hello,

Thank you for the review. iPump-mini does use Bluetooth LE with Core Bluetooth – it is the app's core function. You could not see it because the review device has no MiniMed 780G pump nearby, so only the demo mode (which intentionally uses no Bluetooth) was available.

How the app uses both background modes (source: apps/ios/OpenMinipump/BLE/PumpLink.swift in https://github.com/sgitaize/iPump-mini):

- bluetooth-peripheral: The MiniMed 780G pump connects to the phone, not the other way round. The app therefore runs a GATT server with CBPeripheralManager (pump service 0xFE82 plus Device Information) and advertises it, first for pairing and later for reconnection. The pump subscribes to and writes to these characteristics; this is the encrypted channel over which the read-only status reports arrive.
- bluetooth-central: Over the same link the pump opened, the app also acts as a GATT client via CBCentralManager and reads the pump's own services (Bluetooth SIG Insulin Delivery, CGM and Battery services).
- Background: The pump sends a new sensor glucose value every 5 minutes. The app must keep the link and receive these values while in the background or the screen is locked, so it can update widgets, the Live Activity and optional reminders. Both managers use state restoration (restore identifiers) for this.

Attached is a screen recording on a physical iPhone with a MiniMed 780G showing: Bluetooth permission prompt, pairing with the pump (pump screen visible), live values arriving, the app moving to the background/lock screen and the Live Activity continuing to update.

We have also added this explanation and the recording to the App Review Information notes for future submissions.

Best regards,
Simon Gutjahr
```

**„How can we test the app?“** → Demo-Modus (siehe Review-Notes in Abschnitt 2).

---

## 8. Stand vor der ersten Einreichung

- [x] Demo-Modus für Review (Startbildschirm „Ohne Pumpe ansehen (Demo)“, Einstellungen › Info)
- [x] Datenschutzerklärung: https://simongutjahr.de/impressum/#ipump-mini
- [x] Screenshots 6,9″ DE/EN: `docs/store/screenshots/`
- [x] Code-Doku: MiniMedKit vollständig mit Doku-Kommentaren, `docs/en/architecture.md`
- [x] Zeitkritische Alarme mit Einrichtungsanleitung; kritische Alarme zurückgestellt
- [ ] Export-Compliance beantworten (Abschnitt 9)
- [ ] Rechtliche Kurzprüfung (Medizinprodukte-Verordnung, Kompatibilitäts-Kennung) vor dem App Store; TestFlight und AltStore Classic sind weniger betroffen
- [ ] Optional: Protokollmeldungen der App englisch bzw. lokalisiert, Statusseite der lokalen API zweisprachig

## 9. Verschlüsselung (Export-Compliance)

Apple fragt bei jeder Einreichung, ob die App Verschlüsselung verwendet (US-Exportrecht, EAR Kategorie 5 Teil 2). iPump-mini verwendet:

1. **SAKE-Protokoll zur Pumpe:** AES-128 im CTR-Modus und AES-CMAC (Authentifizierung), um die Bluetooth-Verbindung mit der Pumpe zu verschlüsseln. Standardalgorithmen, umgesetzt mit Apples CommonCrypto, aber außerhalb von Apples Netzwerk-APIs – deshalb zählt das als „eigene“ Verwendung von Verschlüsselung.
2. **HTTPS** über Apples `URLSession` (Nightscout, GitHub) – fällt unter Apples eigene Verschlüsselung.
3. **Schlüsselbund** (iOS) für Secrets.

Antworten in App Store Connect (Vorschlag, keine Rechtsberatung): „Uses encryption: **Yes**“ → „Standard encryption algorithms instead of, or in addition to, Apple's: **Yes**“. Danach fragt Apple, ob eine Ausnahme greift; die Verschlüsselung dient hier der Kommunikation mit einem medizinischen Gerät des Nutzers, nicht der allgemeinen Datenverschlüsselung. Ob das als Ausnahme („medical end-use“) oder als Massenmarkt-Verschlüsselung einzuordnen ist, vor der ersten Einreichung kurz prüfen. Ergebnis als `ITSAppUsesNonExemptEncryption` in `project.yml` (Info.plist) eintragen, dann fragt Apple nicht bei jedem Build erneut. Für TestFlight intern und AltStore Classic spielt das keine Rolle.
