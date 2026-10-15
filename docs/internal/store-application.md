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
| Privacy Policy URL | **fehlt noch** – eigener Abschnitt „iPump-mini“ in https://simongutjahr.de/impressum/#datenschutz |
| Price | Free |
| App Privacy („Nutrition Label“) | Data Not Collected |
| Age Rating | 4+ (keine medizinischen Ratschläge im Sinne der Altersfreigabe; „Medical/Treatment Information: None“ prüfen) |
| Copyright | 2026 Simon Gutjahr |
| Export compliance | Die App verwendet Verschlüsselung (AES/CMAC für das Bluetooth-Protokoll der Pumpe). Vor Einreichung `ITSAppUsesNonExemptEncryption` klären; vermutlich Ausnahme für Standardalgorithmen. |

### App Review Information – Notes (EN)
```
Thank you for reviewing iPump-mini.

PURPOSE
iPump-mini lets people who use a MiniMed 780G insulin pump view the data of their own pump on their iPhone. The pump otherwise only shares data through the manufacturer's app and cloud. iPump-mini reads the data locally over Bluetooth LE, without any server.

READ-ONLY / SAFETY
- The app only reads. It cannot deliver insulin, change pump settings or clear alarms. All requests to the pump pass through a hard-coded allowlist of read-only report requests (source: core/MiniMedKit/Sources/MiniMedKit/Safety/ReadOnlyPolicy.swift in the public repository); anything else is blocked and logged.
- The app is not a medical device and is not intended for treatment decisions. This is stated in the description, in the app (footer on the main screen, About page) and in terms of use that every user must accept on first launch, including an explicit confirmation that the pump's displays and alarms are authoritative.
- Optional notifications are labelled as additional, non-binding reminders; the pump's own alarms stay on.

PRIVACY
No account, no analytics, no data collection. Data stays on the device. An optional upload goes only to a Nightscout server the user operates.

HOW TO REVIEW WITHOUT A PUMP
The app requires a MiniMed 780G pump. For review, a demo mode with simulated values is available: [TODO: Demo-Modus für Release-Builds einbauen, z. B. Einstellungen › Info › 7× auf Version tippen, oder Startbildschirm „Ohne Pumpe ansehen“]. Demo mode shows the graph, widgets, Live Activity and settings with generated data and does not use Bluetooth.

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

## 4. Antrag „Critical Alerts Entitlement“ (Apple)

Formular: developer.apple.com/contact/request/notifications-critical-alerts-entitlement

**App name:** iPump-mini
**Bundle ID:** de.sgitaize.openminipump

**Explain why your app needs critical alerts (EN):**
```
iPump-mini is used by people with type 1 diabetes who wear a MiniMed 780G insulin pump with a continuous glucose sensor. The app reads the user's own pump over Bluetooth and can warn about an urgent low glucose value (default 55 mg/dL / 3.1 mmol/L) and about pump alerts such as "no insulin delivery".

A severe low glucose level is a medical emergency that can lead to unconsciousness, especially during sleep. Many users keep their iPhone silenced or in a Sleep Focus at night. Without critical alerts, an urgent-low warning would be silent exactly when it matters most.

Critical alerts are used only for:
- urgent low glucose (user-configurable threshold, default 55 mg/dL), and
- urgent pump alerts (e.g. insulin delivery stopped).
All other notifications (low, high, rapid change, reminders) are regular or time-sensitive notifications. Users can turn critical alerts off at any time in the app and in iOS Settings.

The app does not replace the pump's own alarms; it is an additional safety net that users explicitly opt into. It is free, open source and collects no data.
```

**Hinweis:** Apple vergibt das Entitlement meist an Apps mit klarem medizinischem oder Sicherheitszweck. Eine Ablehnung ist möglich, weil die App kein Medizinprodukt ist. Dann bleibt „zeitkritisch“.

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
**„Do you have permission to use the manufacturer's protocol / trademarks?“**
```
The app is an independent implementation for interoperability with the user's own device, based on public research (OpenMinimed, GPL-3.0) and the public Bluetooth SIG specifications (Insulin Delivery Service, CGM Service). It contains no code or assets of the manufacturer. Trademarks are used only descriptively to state compatibility, with a clear non-affiliation notice.
```
**„How can we test the app?“** → Demo-Modus (siehe Abschnitt 2, To-do).

---

## 8. Offene Punkte vor der ersten Einreichung

1. **Demo-Modus für Review** auch in Release-Builds (ohne Bluetooth, simulierte Werte, klar gekennzeichnet).
2. **Datenschutzerklärung** mit eigenem Abschnitt iPump-mini auf simongutjahr.de (kein Tracking, keine Daten, optional Nightscout des Nutzers, Schlüsseldatenbank-Abruf von GitHub).
3. **Code-Doku:** Doku-Kommentare für öffentliche Typen in MiniMedKit und die App-Kerne, `docs/en/architecture.md` (Aufbau, Datenfluss, Sicherheitsgrenzen), Protokollmeldungen und Statusseite der lokalen API auf Englisch bzw. lokalisiert.
4. **Screenshots** in den App-Store-Größen (6,9″: 1320 × 2868) mit Demo-Daten, DE und EN.
5. **Export-Compliance** (Verschlüsselung) klären.
6. **Rechtliche Kurzprüfung** (Medizinprodukte-Verordnung, Kompatibilitäts-Kennung) vor App Store; AltStore Classic und TestFlight sind davon weniger betroffen.
7. Kritische Alarme beantragen (Abschnitt 4).
