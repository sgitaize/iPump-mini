// SPDX-License-Identifier: GPL-3.0-or-later
package de.sgitaize.openminipump

/**
 * Texts that come from the protocol library as German source strings (sensor states, modes,
 * pump alert titles). Static UI texts are Android string resources (values/ = German source,
 * values-en/ and values-ru/); these dynamic ones are translated here, with the same English wording as the
 * iOS string catalog (apps/ios/Shared/Localizable.xcstrings).
 */
object L10n {
    private val ru = mapOf(
        "Sensor ok" to "Сенсор работает",
        "Warten auf Kalibrierung" to "Ожидание калибровки",
        "Sensor wird aktualisiert" to "Сенсор обновляется",
        "Kalibrierung erforderlich" to "Требуется калибровка",
        "Kalibriert" to "Откалиброван",
        "Sensorsignal wird gesucht" to "Поиск сигнала сенсора",
        "Kein Sensorsignal" to "Нет сигнала сенсора",
        "Sensor wechseln" to "Замените сенсор",
        "Aufwärmphase" to "Прогрев",
        "SG unter Messbereich" to "Значение сенсора ниже диапазона измерений",
        "SG über Messbereich" to "Значение сенсора выше диапазона измерений",
        "Transmitter-Batterie leer" to "Батарея трансмиттера разряжена",
        "Sensor verbunden" to "Сенсор подключён",
        "Warten auf Aufwärmphase" to "Ожидание прогрева",
        "Kein Sensor gekoppelt" to "Сенсор не сопряжён",
        "Kein Sensor aktiv" to "Нет активного сенсора",
        "Sensorsignal verloren" to "Сигнал сенсора потерян",
        "SmartGuard" to "SmartGuard",
        "Sicherheitsbasal" to "Безопасная базальная подача",
        "Manueller Modus" to "Ручной режим",
        "Keine Insulinabgabe" to "Подача инсулина прекращена",
        "Pumpenfehler" to "Ошибка помпы",
        "Bolus gestoppt" to "Болюс остановлен",
        "Maximale Füllmenge erreicht" to "Достигнут максимальный объём заполнения",
        "Batterie einsetzen" to "Установите батарею",
        "BZ nach Bolus prüfen" to "Проверьте глюкозу крови после болюса",
        "Pumpenbatterie schwach" to "Батарея помпы разряжается",
        "Reservoir fast leer" to "В резервуаре мало инсулина",
        "Persönliche Erinnerung" to "Личное напоминание",
        "Katheterwechsel-Erinnerung" to "Напоминание о замене инфузионного набора",
        "Aktives Insulin gelöscht" to "Данные об активном инсулине сброшены",
        "Jetzt kalibrieren" to "Выполните калибровку",
        "Kalibrierung nicht akzeptiert" to "Калибровка отклонена",
        "Keine Kalibrierung erfolgt" to "Калибровка не выполнена",
        "Sensorfehler" to "Ошибка сенсора",
        "Niedriger SG-Wert" to "Низкое значение сенсора",
        "Abschaltung bei Tief" to "Остановка при низкой глюкозе",
        "Alarm vor Tief" to "Оповещение перед снижением глюкозы",
        "Basalabgabe fortgesetzt" to "Базальная подача возобновлена",
        "Abschaltung bei Grenzwert" to "Остановка на нижней границе",
        "Abschaltung vor Tief" to "Остановка перед снижением глюкозы",
        "Abschaltung bei Tief: Zeit abgelaufen" to "Остановка при низкой глюкозе: время истекло",
        "Manuelle Fortsetzung" to "Подача возобновлена вручную",
        "Hoher SG-Wert" to "Высокое значение сенсора",
        "SmartGuard beendet: hoher SG" to "SmartGuard выключен: высокая глюкоза",
        "SmartGuard beendet" to "SmartGuard выключен",
        "SmartGuard: minimale Abgabe" to "SmartGuard: минимальная подача",
        "SmartGuard: maximale Abgabe" to "SmartGuard: максимальная подача",
        "SmartGuard aus" to "SmartGuard выключен",
        "Sehr niedriger SG-Wert" to "Очень низкое значение сенсора",
        "SmartGuard: Bolus empfohlen" to "SmartGuard: рекомендуется болюс",
        "Seit 3 Stunden hoch" to "Высокая глюкоза три часа",
        "Kalibrierung empfohlen" to "Рекомендуется калибровка",
        "Erste Kalibrierung erfolgreich" to "Первая калибровка выполнена",
        "Frühe Kalibrierung" to "Ранняя калибровка",
        "Kalibrier-Erinnerung" to "Напоминание о калибровке",
    )

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

    /** Translate known protocol texts according to the app locale; preserve unknown source texts. */
    fun tr(german: String): String {
        val lang = OpenMinipumpApp.instance.resources.configuration.locales[0].language
        val translations = when (lang) {
            "en" -> en
            "ru" -> ru
            else -> return german
        }
        translations[german]?.let { return it }
        val alertPrefix = when (lang) {
            "ru" -> "Оповещение помпы "
            else -> "Pump alert "
        }
        val unknownPrefix = when (lang) {
            "ru" -> "Неизвестно: "
            else -> "Unknown "
        }
        if (german.startsWith("Pumpenmeldung ")) return alertPrefix + german.removePrefix("Pumpenmeldung ")
        if (german.startsWith("Unbekannt ")) return unknownPrefix + german.removePrefix("Unbekannt ")
        return german
    }
}

