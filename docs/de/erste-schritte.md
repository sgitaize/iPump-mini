# iPump-mini – Erste Schritte

*English: [getting-started.md](../en/getting-started.md)*

> **Wichtig:** iPump-mini ist kein Medizinprodukt und nicht für Therapieentscheidungen gedacht. Maßgeblich sind immer die Anzeigen und Alarme der Pumpe. Die Alarme der Pumpe bleiben eingeschaltet. Beim ersten Start musst du den Nutzungsbedingungen zustimmen.

Die Einrichtung dauert etwa 10 Minuten. Halte Pumpe und Handy nah beieinander und sorge für Internet (für die Schlüsseldatenbank).

## Was du brauchst
- **iPhone** mit iOS 17 oder neuer **oder Android-Handy** mit Android 10 oder neuer
- MiniMed 780G (getestet mit Firmware 6.23W) mit Simplera Sync oder Guardian 4
- Die Android-Version ist eine **Beta** und noch nicht mit einer echten Pumpe getestet.

## Überblick
1. App installieren
2. MiniMed Mobile an der Pumpe entkoppeln
3. Alte Bluetooth-Kopplung am Handy löschen
4. App starten, Nutzungsbedingungen
5. Schlüsseldatenbank von OpenMinimed laden
6. Berechtigungen erlauben
7. Sensor wählen
8. Pumpe koppeln
9. Prüfen, ob Werte ankommen

## 1. App installieren
- **iPhone:** aus dem App Store. Alternativ selbst bauen, siehe [Selbst bauen](selbst-bauen.md).
- **Android:** Auf der [Release-Seite](https://github.com/sgitaize/iPump-mini/releases) beim neuesten Android-Release die Datei `ipump-mini.apk` auf dem Handy herunterladen und öffnen. Android fragt, ob der Browser bzw. die Dateien-App Apps installieren darf: einmal erlauben, dann „Installieren“. Hast du noch die erste Beta (`de.sgitaize.openminipump`), deinstalliere sie vorher.

## 2. MiniMed Mobile an der Pumpe entkoppeln
Die Pumpe nimmt nur **ein** Mobilgerät an. Ist MiniMed Mobile (oder eine andere App) gekoppelt, muss diese Kopplung zuerst weg.

1. An der Pumpe: **Menü › Kopplungsoptionen › Gekoppelte Geräte**.
2. Das Handy bzw. „MiniMed Mobile“ auswählen › **Entkoppeln** › bestätigen.

Nur das Mobilgerät entkoppeln, **nicht den Sensor**. Die Bezeichnungen können je nach Softwarestand leicht abweichen. Danach lädt MiniMed Mobile keine Daten mehr zu CareLink hoch.

## 3. Alte Bluetooth-Kopplung am Handy löschen
War das Handy schon mit der Pumpe gekoppelt, kennt es sie noch und stört die neue Kopplung.

- **Android:** Einstellungen › Verbundene Geräte (bei Samsung: Verbindungen › Bluetooth) › Zahnrad neben der Pumpe › **Entkoppeln**.
- **iPhone:** Einstellungen › Bluetooth › ⓘ neben der Pumpe › **Dieses Gerät ignorieren**.
- **MiniMed Mobile schließen oder deinstallieren**, damit die App die Verbindung nicht wieder übernimmt.

Taucht die Pumpe nicht in der Liste auf, ist nichts zu tun.

## 4. App starten, Nutzungsbedingungen
Beim ersten Start stimmst du den Nutzungsbedingungen zu. Sie sind später unter Einstellungen › Info nachlesbar. Wer sich erst umsehen will, kann den **Demo-Modus** wählen (simulierte Werte, kein Bluetooth).

## 5. Schlüsseldatenbank laden
Die App braucht für die verschlüsselte Verbindung die SAKE-Schlüsseldatenbank „Mobile Application ↔ Insulin Pump“. Sie ist **nicht** in der App enthalten, sondern wird aus der öffentlichen Dokumentation des Projekts [OpenMinimed](https://github.com/OpenMinimed) geladen.

- In der Ersteinrichtung oder unter Einstellungen › Pumpe › Schlüsseldatenbank auf **„Von OpenMinimed laden“** tippen. Die App lädt [key_databases.md](https://github.com/OpenMinimed/Documentation/blob/main/key_databases.md) und übernimmt den passenden Block. Geprüft werden Prüfsumme und Gerätetyp.
- Alternativ: eine eigene Adresse angeben oder den Hex-Block einfügen.

## 6. Berechtigungen erlauben
- **Android:** „Geräte in der Nähe“ (Bluetooth) und Benachrichtigungen erlauben. Unter Einstellungen › Pumpe › Akku-Optimierung für iPump-mini **„Nicht optimieren“** wählen, sonst bremst Android die App im Hintergrund aus.
- **iPhone:** Bluetooth und Mitteilungen erlauben.

Ohne Mitteilungen gibt es keine Alarme. Fallstricke stehen unten unter „Alarme“.

## 7. Sensor wählen
Simplera Sync (ohne Transmitter) oder Guardian 4 (mit Transmitter). Danach richtet sich, welche Werte angezeigt werden. Ändern kannst du das später unter Einstellungen › Sensor.

## 8. Pumpe koppeln
1. In der App **„Pumpe koppeln“** öffnen. Die App zeigt ihren Namen, z. B. **„Mobile 123456“**. App im Vordergrund lassen, Handy entsperrt.
2. An der Pumpe: **Menü › Kopplungsoptionen › Neues Gerät koppeln**.
3. Die Pumpe sucht und zeigt „Mobile …“ mit dem Namen aus der App. Auswählen und bestätigen.
4. Auf dem Handy erscheint eine **Bluetooth-Kopplungsanfrage**: „Koppeln“ antippen.
5. Die Pumpe meldet die erfolgreiche Kopplung.

Klappt es nicht: Schritte 2 und 3 prüfen (alte Kopplung an Pumpe und Handy wirklich gelöscht?), Bluetooth am Handy aus- und einschalten und neu starten.

## 9. Prüfen, ob Werte ankommen
Nach kurzer Zeit erscheinen der aktuelle Wert und der Pumpenstatus. Die Historie der letzten Stunden wird nachgeladen. Danach meldet sich die Pumpe etwa alle 5 Minuten von selbst. Vergleiche die ersten Werte mit der Anzeige der Pumpe.

## Im Alltag
- **App nicht wegwischen.**
  - **iPhone:** Die Pumpe weckt die App alle 5 Minuten. Das klappt nur, solange sie im Hintergrund läuft. Wurde sie beendet, erinnert eine Mitteilung daran.
  - **Android:** Ein Dienst mit dauerhafter Mitteilung hält die App erreichbar. Die Mitteilung zeigt den aktuellen Wert. Nach einem Neustart des Handys startet der Dienst von selbst.
- **Bluetooth an lassen.** Nach dem Einschalten verbindet sich die Pumpe von selbst neu.
- **Keine Verbindung?** Pumpe in Reichweite bringen, App öffnen. Hilft das nach einigen Minuten nicht, Bluetooth kurz aus- und wieder einschalten. Erst wenn auch das nicht hilft, neu koppeln (ab Schritt 2).
- **Zeitumstellung:** Die App erkennt, wenn die Pumpenuhr verstellt wurde (z. B. Sommer-/Winterzeit), und korrigiert die Zeiten der Werte selbst.
- **Widgets (iPhone):** Home- oder Sperrbildschirm lange drücken › Bearbeiten › Widget hinzufügen › iPump-mini. Aussehen unter Einstellungen › Widgets.
- **Live-Aktivität / Dynamic Island (iPhone):** startet beim Öffnen der App. iOS beendet sie nach 8 Stunden.
- **Aussehen:** Hell/Dunkel/System, Einheit (mg/dL oder mmol/L) und Zielbereich unter Einstellungen › Aussehen. Sprache: iPhone in der App, Android in den Android-Einstellungen der App.
- **Nightscout (optional):** URL und API-Secret unter Einstellungen › Nightscout. Neue Werte werden sofort hochgeladen, dazu Pumpenstatus und Behandlungen.
- **Lokale API (optional):** Nightscout-kompatibel auf Port 17580, z. B. für Pebble-Watchfaces, siehe [api.md](api.md).

## Alarme
- **Pumpenalarme:** Die App gibt Meldungen der Pumpe weiter. Quittiert werden sie an der Pumpe.
- **Testen:** Unter Einstellungen › Alarme „Test-Alarm senden“, Handy sperren und prüfen, ob der Alarm mit Ton kommt.
- **Android – Bitte nicht stören:** Im Benachrichtigungskanal „Dringende Alarme“ „Bitte nicht stören ignorieren“ einschalten oder iPump-mini als Ausnahme hinzufügen.
- **iPhone – Fokus/Schlafen:** Ein Fokus hält normale Mitteilungen zurück. iPump-mini im Fokus unter „Erlaubte Apps“ hinzufügen, sonst bleiben Alarme nachts stumm.
- **iPhone – Stummschalter:** Bei stummgeschaltetem iPhone kommen Alarme ohne Ton. Nur „kritische Alarme“ kommen durch. Dafür braucht es eine Freigabe von Apple, die selbst gebaute Versionen nicht haben.

Die App enthält eine Kurzfassung dieser Anleitung unter Einstellungen › Info › Anleitung.
