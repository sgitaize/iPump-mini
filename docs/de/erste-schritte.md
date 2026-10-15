# iPump-mini – Erste Schritte

*English: [getting-started.md](../en/getting-started.md)*

> **Wichtig:** iPump-mini ist kein Medizinprodukt und nicht für Therapieentscheidungen gedacht. Maßgeblich sind immer die Anzeigen und Alarme der Pumpe. Die Alarme der Pumpe bleiben eingeschaltet. Beim ersten Start musst du den Nutzungsbedingungen zustimmen.

## Was du brauchst
- iPhone mit iOS 17 oder neuer
- MiniMed 780G (getestet mit Firmware 6.23W) mit Simplera Sync oder Guardian 4
- Zum Installieren: AltStore/SideStore (sobald veröffentlicht) oder einen Mac mit Xcode (siehe [Selbst bauen](selbst-bauen.md))

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
