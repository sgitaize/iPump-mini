# iPump-mini – Get started

*[English version below](#english)*

> **Wichtig:** iPump-mini ist kein Medizinprodukt und nicht für Therapieentscheidungen gedacht. Maßgeblich sind immer die Anzeigen und Alarme der Pumpe. Die Alarme der Pumpe bleiben eingeschaltet. Beim ersten Start musst du den Nutzungsbedingungen zustimmen.

## Was du brauchst
- iPhone mit iOS 17 oder neuer
- MiniMed 780G (getestet mit Firmware 6.23W) mit Simplera Sync oder Guardian 4
- Zum Installieren: AltStore/SideStore (sobald veröffentlicht) oder einen Mac mit Xcode (siehe [Selbst bauen](setup-ios.md))

## 1. Installieren und Nutzungsbedingungen
Beim ersten Start wählst du die Sprache (Deutsch/English, Standard: wie das iPhone) und stimmst den Nutzungsbedingungen zu. Sie sind später unter Einstellungen › Info nachlesbar.

## 2. Schlüsseldatenbank laden
Die App braucht für die verschlüsselte Verbindung die SAKE-Schlüsseldatenbank „Mobile Application ↔ Insulin Pump“. Sie ist **nicht** in der App enthalten.

- In der Ersteinrichtung oder unter Einstellungen › Pumpe › Schlüsseldatenbank auf **„Von OpenMinimed laden“** tippen. Die App lädt die öffentliche Seite [key_databases.md](https://github.com/OpenMinimed/Documentation/blob/main/key_databases.md) und übernimmt den passenden Block. Geprüft werden Prüfsumme und Gerätetyp.
- Alternativ: eine eigene Adresse angeben oder den Hex-Block einfügen.

## 3. Mitteilungen erlauben
Ohne Erlaubnis gibt es keine Alarme. In der Ersteinrichtung auf „Mitteilungen erlauben“ tippen.

**Fallstricke:**
- **Fokus/Schlafen:** Ein Fokus hält normale Mitteilungen zurück. iPump-mini im Fokus unter „Erlaubte Apps“ hinzufügen, sonst bleiben Alarme nachts stumm.
- **Stummschalter:** Bei stummgeschaltetem iPhone kommen Alarme ohne Ton. Nur „kritische Alarme“ kommen durch; die braucht eine Freigabe von Apple, die selbst gebaute und AltStore-Versionen nicht haben.
- **Zeitkritisch:** Gibt es nur mit einem bezahlten Entwickler-Account. Mit kostenloser Apple-ID kommen Alarme als normale Mitteilungen.
- **Pumpenalarme:** Die App gibt Meldungen der Pumpe weiter, quittiert werden sie an der Pumpe.

## 4. Sensor wählen
Simplera Sync (ohne Transmitter) oder Guardian 4 (mit Transmitter). Danach richtet sich, welche Werte angezeigt werden.

## 5. Pumpe koppeln
1. Die Pumpe nimmt nur **ein** Mobilgerät an. Ist MiniMed Mobile gekoppelt, diese Kopplung zuerst an der Pumpe entfernen.
2. In der App „Pumpe koppeln“ öffnen. App im Vordergrund lassen, iPhone entsperrt.
3. An der Pumpe: Menü › Kopplungsoptionen › Neues Gerät koppeln. „Mobile …“ (Name aus der App) wählen und bestätigen.
4. Auf dem iPhone die Bluetooth-Kopplungsanfrage bestätigen.
5. Nach kurzer Zeit erscheinen die ersten Werte.

## 6. Im Alltag
- **App nicht wegwischen.** Die Pumpe weckt die App alle 5 Minuten; das klappt nur, solange sie im Hintergrund läuft. Wurde sie beendet, erinnert eine Mitteilung daran.
- **Keine Verbindung?** Pumpe in Reichweite, App öffnen. Nach einigen Minuten ohne Erfolg: Bluetooth in den iPhone-Einstellungen aus- und einschalten. Erst danach neu koppeln.
- **Widgets:** Home- oder Sperrbildschirm lange drücken › Bearbeiten › Widget hinzufügen › iPump-mini. Aussehen unter Einstellungen › Widgets.
- **Live-Aktivität / Dynamic Island:** startet beim Öffnen der App; iOS beendet sie nach 8 Stunden.
- **Aussehen:** Hell/Dunkel/System, Sprache, Einheit (mg/dL oder mmol/L) und Zielbereich unter Einstellungen › Aussehen.
- **Nightscout (optional):** URL und API-Secret unter Einstellungen › Nightscout. Neue Werte werden sofort hochgeladen, dazu Pumpenstatus und Behandlungen.
- **Lokale API (optional):** Nightscout-kompatibel auf Port 17580, siehe [api.md](api.md).

Die App enthält dieselbe Anleitung unter Einstellungen › Info › Anleitung.

---

## English

> **Important:** iPump-mini is not a medical device and not intended for treatment decisions. The pump's displays and alarms are always authoritative; keep the pump's alarms turned on. You have to accept the terms of use on first start.

**You need:** an iPhone with iOS 17 or later; a MiniMed 780G (tested with firmware 6.23W) with Simplera Sync or Guardian 4; AltStore/SideStore (once released) or a Mac with Xcode ([build it yourself](building.md)).

1. **Install and accept the terms.** Pick the language (German/English; default follows the iPhone).
2. **Load the key database.** Setup or Settings › Pump › Key database › **“Load from OpenMinimed”**. The app downloads the public [key_databases.md](https://github.com/OpenMinimed/Documentation/blob/main/key_databases.md) page and picks the “Mobile Application ↔ Insulin Pump” block (checked by checksum and device type). You can also enter another address or paste the hex block.
3. **Allow notifications.** Pitfalls:
   - A Focus (including Sleep) holds back normal notifications. Add iPump-mini to “Allowed apps”.
   - With the silent switch on, alarms have no sound. Only critical alerts break through, which needs an Apple approval that self-built and AltStore builds don't have.
   - Time-sensitive alerts need a paid developer account.
   - Pump alerts are forwarded but must be cleared on the pump.
4. **Choose your sensor:** Simplera Sync (no transmitter) or Guardian 4.
5. **Pair the pump.**
   - The pump accepts one mobile device, so remove a MiniMed Mobile pairing first.
   - Open “Pair pump”, keep the app in the foreground.
   - On the pump: Menu › Pairing options › Pair new device. Select “Mobile …”, then confirm the Bluetooth request on the iPhone.
6. **Day to day:**
   - Don't swipe the app away; the pump wakes it every 5 minutes.
   - No connection: open the app with the pump in range, then toggle Bluetooth in Settings, and only then pair again.
   - Widgets, Live Activity, appearance (theme, language, unit, target range), optional Nightscout upload and the local API (port 17580) are in Settings.
