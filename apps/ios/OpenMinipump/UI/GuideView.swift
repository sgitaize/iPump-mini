// SPDX-License-Identifier: GPL-3.0-or-later
import SwiftUI

/// In-app manual: setup, background operation and the notification pitfalls.
struct GuideView: View {
    var body: some View {
        List {
            Section("Einrichtung") {
                GuideItem(icon: "key", title: "Schlüsseldatenbank",
                          text: "Die App braucht einmalig die Schlüsseldatenbank für die verschlüsselte Verbindung. Einstellungen › Pumpe › Schlüsseldatenbank › „Von OpenMinimed laden“.")
                GuideItem(icon: "link", title: "Pumpe koppeln",
                          text: "Die Pumpe nimmt nur ein Mobilgerät an. Eine Kopplung mit MiniMed Mobile vorher an der Pumpe entfernen. Dann „Pumpe koppeln“ in der App öffnen und der Anleitung folgen.")
                GuideItem(icon: "sensor", title: "Sensor wählen",
                          text: "Simplera Sync hat keinen Transmitter, Guardian 4 schon. Danach richtet sich, welche Werte angezeigt werden.")
            }

            Section("Im Hintergrund") {
                GuideItem(icon: "iphone", title: "App nicht wegwischen",
                          text: "Die Pumpe weckt die App alle 5 Minuten. Das klappt nur, solange die App im Hintergrund läuft. Wird sie im App-Umschalter weggewischt, kommen keine Werte mehr. Die App erinnert dich dann per Mitteilung.")
                GuideItem(icon: "antenna.radiowaves.left.and.right", title: "Bluetooth an lassen",
                          text: "Bluetooth im Kontrollzentrum auszuschalten trennt die Pumpe nur bis zum nächsten Einschalten. In den Einstellungen ausgeschaltet bleibt die Verbindung weg.")
                GuideItem(icon: "arrow.clockwise", title: "Keine Verbindung?",
                          text: "Pumpe in Reichweite bringen, App öffnen. Hilft das nach einigen Minuten nicht, Bluetooth in den iPhone-Einstellungen kurz aus- und wieder einschalten. Erst wenn auch das nicht hilft, neu koppeln.")
            }

            Section("Mitteilungen und Alarme") {
                GuideItem(icon: "exclamationmark.triangle", title: "Die Pumpe ist maßgeblich",
                          text: "Die Alarme der App sind eine Ergänzung. Lass die Alarme der Pumpe immer eingeschaltet.", tint: .orange)
                GuideItem(icon: "bell.badge", title: "Mitteilungen erlauben",
                          text: "Ohne Erlaubnis kommen keine Alarme. Prüfen unter iPhone-Einstellungen › Mitteilungen › iPump-mini: Mitteilungen, Töne und Sperrbildschirm an.")
                GuideItem(icon: "moon", title: "Fokus und Schlafmodus",
                          text: "Ein Fokus (auch „Schlafen“) hält Mitteilungen zurück. Dringende Alarme kommen als zeitkritische Mitteilung durch, wenn du das im Fokus erlaubst: Einstellungen › Fokus › Schlafen › Apps › iPump-mini hinzufügen oder „Zeitkritische Mitteilungen“ erlauben.")
                GuideItem(icon: "speaker.slash", title: "Stummschalter",
                          text: "Bei stummgeschaltetem iPhone kommen Alarme ohne Ton – auch zeitkritische. Nachts das iPhone nicht stumm schalten.")
                GuideItem(icon: "clock.badge.exclamationmark", title: "Zeitkritische Mitteilungen",
                          text: "Dringende Alarme kommen als zeitkritische Mitteilung. Einschalten unter iPhone-Einstellungen › Mitteilungen › iPump-mini › „Zeitkritische Mitteilungen“. Schritt für Schritt: Einstellungen › Alarme › So richtest du es ein.")
                GuideItem(icon: "zzz", title: "Stummschalten",
                          text: "Einzelne Alarme lassen sich direkt in der Mitteilung für 15, 30 oder 60 Minuten stummschalten. „Dringend niedrig“ lässt sich nicht global stummschalten.")
            }

            Section("Widgets") {
                GuideItem(icon: "square.grid.2x2", title: "Widgets hinzufügen",
                          text: "Home-Bildschirm oder Sperrbildschirm lange drücken › Bearbeiten › Widget hinzufügen › iPump-mini. Aussehen unter Einstellungen › Widgets.")
                GuideItem(icon: "platter.filled.top.iphone", title: "Live-Aktivität",
                          text: "Zeigt Wert, Trend und Änderung in der Dynamic Island. iOS beendet sie nach spätestens 8 Stunden; beim nächsten Öffnen der App startet sie neu.")
            }

            Section("Daten weitergeben") {
                GuideItem(icon: "icloud.and.arrow.up", title: "Nightscout",
                          text: "Optional: lädt Werte, Pumpenstatus und Behandlungen in deine eigene Nightscout-Instanz. URL und API-Secret unter Einstellungen › Nightscout.")
                GuideItem(icon: "network", title: "Lokale API",
                          text: "Nightscout-kompatible Schnittstelle auf Port 17580, für Uhren und andere Apps. Im WLAN nur mit API-Secret.")
            }
        }
        .navigationTitle("Anleitung")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct GuideItem: View {
    let icon: String
    let title: LocalizedStringKey
    let text: LocalizedStringKey
    var tint: Color = .accentColor

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.body)
                .foregroundStyle(tint)
                .frame(width: 26)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.subheadline.weight(.semibold))
                Text(text).font(.subheadline).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}
