// SPDX-License-Identifier: GPL-3.0-or-later
package de.sgitaize.openminipump

/**
 * Texts that come from the protocol library as German source strings (sensor states, modes,
 * pump alert titles). Static UI texts are Android string resources (values/ = German source,
 * values-en/); these dynamic ones are translated here, with the same English wording as the
 * iOS string catalog (apps/ios/Shared/Localizable.xcstrings).
 */
object L10n {
    private val en = mapOf(
        "Sensor ok" to "Sensor ok",
        "Warten auf Kalibrierung" to "Waiting for calibration",
        "Sensor wird aktualisiert" to "Sensor updating",
        "Kalibrierung erforderlich" to "Calibration required",
        "Kalibriert" to "Calibrated",
        "Sensorsignal wird gesucht" to "Searching for sensor signal",
        "Kein Sensorsignal" to "No sensor signal",
        "Sensor wechseln" to "Change sensor",
        "Aufwärmphase" to "Warm-up",
        "SG unter Messbereich" to "SG below range",
        "SG über Messbereich" to "SG above range",
        "Transmitter-Batterie leer" to "Transmitter battery empty",
        "Sensor verbunden" to "Sensor connected",
        "Warten auf Aufwärmphase" to "Waiting for warm-up",
        "Kein Sensor gekoppelt" to "No sensor paired",
        "Kein Sensor aktiv" to "No active sensor",
        "Sensorsignal verloren" to "Lost sensor signal",
        "SmartGuard" to "SmartGuard",
        "Sicherheitsbasal" to "Safe basal",
        "Manueller Modus" to "Manual mode",
        "Keine Insulinabgabe" to "No insulin delivery",
        "Pumpenfehler" to "Pump error",
        "Bolus gestoppt" to "Bolus stopped",
        "Maximale Füllmenge erreicht" to "Max fill reached",
        "Batterie einsetzen" to "Insert battery",
        "BZ nach Bolus prüfen" to "Check BG after bolus",
        "Pumpenbatterie schwach" to "Pump battery low",
        "Reservoir fast leer" to "Low reservoir",
        "Persönliche Erinnerung" to "Personal reminder",
        "Katheterwechsel-Erinnerung" to "Set change reminder",
        "Aktives Insulin gelöscht" to "Active insulin cleared",
        "Jetzt kalibrieren" to "Calibrate now",
        "Kalibrierung nicht akzeptiert" to "Calibration not accepted",
        "Keine Kalibrierung erfolgt" to "Calibration not done",
        "Sensorfehler" to "Sensor error",
        "Niedriger SG-Wert" to "Low SG",
        "Abschaltung bei Tief" to "Suspend on low",
        "Alarm vor Tief" to "Alert before low",
        "Basalabgabe fortgesetzt" to "Basal delivery resumed",
        "Abschaltung bei Grenzwert" to "Suspend on low limit",
        "Abschaltung vor Tief" to "Suspend before low",
        "Abschaltung bei Tief: Zeit abgelaufen" to "Suspend on low: time expired",
        "Manuelle Fortsetzung" to "Manual resume",
        "Hoher SG-Wert" to "High SG",
        "SmartGuard beendet: hoher SG" to "SmartGuard exit: high SG",
        "SmartGuard beendet" to "SmartGuard exit",
        "SmartGuard: minimale Abgabe" to "SmartGuard: min delivery",
        "SmartGuard: maximale Abgabe" to "SmartGuard: max delivery",
        "SmartGuard aus" to "SmartGuard off",
        "Sehr niedriger SG-Wert" to "Very low SG",
        "SmartGuard: Bolus empfohlen" to "SmartGuard: bolus recommended",
        "Seit 3 Stunden hoch" to "High for 3 hours",
        "Kalibrierung empfohlen" to "Calibration recommended",
        "Erste Kalibrierung erfolgreich" to "First calibration successful",
        "Frühe Kalibrierung" to "Early calibration",
        "Kalibrier-Erinnerung" to "Calibration reminder",
    )

    /** English if the app runs in English, otherwise the German source text (like values/). */
    fun tr(german: String): String {
        val lang = OpenMinipumpApp.instance.resources.configuration.locales[0].language
        if (lang != "en") return german
        en[german]?.let { return it }
        if (german.startsWith("Pumpenmeldung ")) return "Pump alert " + german.removePrefix("Pumpenmeldung ")
        if (german.startsWith("Unbekannt ")) return "Unknown " + german.removePrefix("Unbekannt ")
        return german
    }
}
