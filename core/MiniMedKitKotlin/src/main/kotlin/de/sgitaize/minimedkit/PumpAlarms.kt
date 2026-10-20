// SPDX-License-Identifier: GPL-3.0-or-later
// Pump alert types (Annunciation Type) with German texts and categories for the alarm
// settings. Type values from OpenMinimed (history/data.py, partly guessed there); the
// texts are our own wording. Same table as the Swift package (PumpAlarms.swift).
package de.sgitaize.minimedkit

/** Groups of pump alerts the user can switch on or off as app notifications. */
enum class PumpAlarmCategory {
    DELIVERY,     // insulin delivery stopped / occlusion / faults
    SUPPLIES,     // reservoir, battery
    SENSOR,       // signal, change sensor, sensor error
    CALIBRATION,  // calibrate now / recommended / not accepted
    GLUCOSE,      // the pump's own low/high/suspend alerts
    SMART_GUARD,  // SmartGuard exits and limits
    REMINDERS,    // personal, set change, BG check after bolus
    OTHER,
}

/** Display data for one pump alert type: German source title (localised by the app), category and urgency. */
data class PumpAlarmInfo(val title: String, val category: PumpAlarmCategory, val urgent: Boolean)

/** Table of known 780G annunciation types (IDS annunciation `type & 0x0FFF`). */
object PumpAlarms {
    /** Info for an annunciation type; unknown types get a generic title in the category OTHER. */
    fun info(type: Int): PumpAlarmInfo =
        table[type] ?: PumpAlarmInfo("Pumpenmeldung 0x%04X".format(type), PumpAlarmCategory.OTHER, false)

    private fun i(title: String, category: PumpAlarmCategory, urgent: Boolean = false) = PumpAlarmInfo(title, category, urgent)

    private val table: Map<Int, PumpAlarmInfo> = mapOf(
        0x0007 to i("Keine Insulinabgabe", PumpAlarmCategory.DELIVERY, true),
        0x0008 to i("Pumpenfehler", PumpAlarmCategory.DELIVERY, true),
        0x0033 to i("Bolus gestoppt", PumpAlarmCategory.DELIVERY, true),
        0x0047 to i("Maximale Füllmenge erreicht", PumpAlarmCategory.DELIVERY),
        0x0048 to i("Maximale Füllmenge erreicht", PumpAlarmCategory.DELIVERY),
        0x0054 to i("Batterie einsetzen", PumpAlarmCategory.SUPPLIES, true),
        0x0067 to i("BZ nach Bolus prüfen", PumpAlarmCategory.REMINDERS),
        0x0068 to i("Pumpenbatterie schwach", PumpAlarmCategory.SUPPLIES),
        0x0069 to i("Reservoir fast leer", PumpAlarmCategory.SUPPLIES),
        0x006A to i("Reservoir fast leer", PumpAlarmCategory.SUPPLIES),
        0x006C to i("Persönliche Erinnerung", PumpAlarmCategory.REMINDERS),
        0x006D to i("Katheterwechsel-Erinnerung", PumpAlarmCategory.REMINDERS),
        0x0075 to i("Aktives Insulin gelöscht", PumpAlarmCategory.OTHER),
        0x0307 to i("Jetzt kalibrieren", PumpAlarmCategory.CALIBRATION),
        0x0308 to i("Kalibrierung nicht akzeptiert", PumpAlarmCategory.CALIBRATION),
        0x0309 to i("Sensor wechseln", PumpAlarmCategory.SENSOR),
        0x030A to i("Sensor wechseln", PumpAlarmCategory.SENSOR),
        0x030C to i("Sensorsignal verloren", PumpAlarmCategory.SENSOR),
        0x0312 to i("Keine Kalibrierung erfolgt", PumpAlarmCategory.CALIBRATION),
        0x0315 to i("Sensor wechseln", PumpAlarmCategory.SENSOR),
        0x031E to i("Sensor verbunden", PumpAlarmCategory.SENSOR),
        0x0321 to i("Sensorfehler", PumpAlarmCategory.SENSOR),
        0x0322 to i("Niedriger SG-Wert", PumpAlarmCategory.GLUCOSE),
        0x0323 to i("Abschaltung bei Tief", PumpAlarmCategory.GLUCOSE, true),
        0x0325 to i("Alarm vor Tief", PumpAlarmCategory.GLUCOSE),
        0x0327 to i("Basalabgabe fortgesetzt", PumpAlarmCategory.GLUCOSE),
        0x0329 to i("Abschaltung bei Grenzwert", PumpAlarmCategory.GLUCOSE, true),
        0x032A to i("Abschaltung vor Tief", PumpAlarmCategory.GLUCOSE),
        0x032B to i("Abschaltung vor Tief", PumpAlarmCategory.GLUCOSE),
        0x032E to i("Abschaltung bei Tief: Zeit abgelaufen", PumpAlarmCategory.GLUCOSE, true),
        0x032F to i("Manuelle Fortsetzung", PumpAlarmCategory.GLUCOSE),
        0x0330 to i("Hoher SG-Wert", PumpAlarmCategory.GLUCOSE),
        0x0331 to i("Hoher SG-Wert", PumpAlarmCategory.GLUCOSE),
        0x0333 to i("SmartGuard beendet: hoher SG", PumpAlarmCategory.SMART_GUARD),
        0x0334 to i("SmartGuard beendet", PumpAlarmCategory.SMART_GUARD),
        0x0335 to i("SmartGuard: minimale Abgabe", PumpAlarmCategory.SMART_GUARD),
        0x0336 to i("SmartGuard: maximale Abgabe", PumpAlarmCategory.SMART_GUARD),
        0x033A to i("SmartGuard aus", PumpAlarmCategory.SMART_GUARD),
        0x033B to i("Sehr niedriger SG-Wert", PumpAlarmCategory.GLUCOSE, true),
        0x0341 to i("SmartGuard: Bolus empfohlen", PumpAlarmCategory.SMART_GUARD),
        0x0344 to i("Seit 3 Stunden hoch", PumpAlarmCategory.GLUCOSE),
        0x0345 to i("Kalibrierung empfohlen", PumpAlarmCategory.CALIBRATION),
        0x034B to i("Erste Kalibrierung erfolgreich", PumpAlarmCategory.CALIBRATION),
        0x034C to i("Frühe Kalibrierung", PumpAlarmCategory.CALIBRATION),
        0x0365 to i("Kalibrier-Erinnerung", PumpAlarmCategory.CALIBRATION),
    )
}
