// SPDX-License-Identifier: GPL-3.0-or-later
// Pump alert types (Annunciation Type) with German texts and categories for the alarm
// settings. Type values from OpenMinimed (history/data.py, partly guessed there); the
// texts are our own wording.
import Foundation

public enum PumpAlarmCategory: String, CaseIterable, Codable, Sendable, Identifiable {
    case delivery      // insulin delivery stopped / occlusion / faults
    case supplies      // reservoir, battery
    case sensor        // signal, change sensor, sensor error
    case calibration   // calibrate now / recommended / not accepted
    case glucose       // the pump's own low/high/suspend alerts
    case smartGuard    // SmartGuard exits and limits
    case reminders     // personal, set change, BG check after bolus
    case other

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .delivery: "Insulinabgabe"
        case .supplies: "Reservoir & Batterie"
        case .sensor: "Sensor"
        case .calibration: "Kalibrierung"
        case .glucose: "Glukose-Alarme der Pumpe"
        case .smartGuard: "SmartGuard"
        case .reminders: "Erinnerungen"
        case .other: "Sonstige"
        }
    }
}

public struct PumpAlarmInfo: Sendable {
    public let title: String
    public let category: PumpAlarmCategory
    /// Delivery stopped, severe low and similar: always worth a critical/time-sensitive alert.
    public let urgent: Bool
}

public enum PumpAlarms {
    public static func info(for type: UInt16) -> PumpAlarmInfo {
        table[type] ?? PumpAlarmInfo(title: String(format: "Pumpenmeldung 0x%04X", type), category: .other, urgent: false)
    }

    private static let table: [UInt16: PumpAlarmInfo] = [
        0x0007: .init(title: "Keine Insulinabgabe", category: .delivery, urgent: true),
        0x0008: .init(title: "Pumpenfehler", category: .delivery, urgent: true),
        0x0033: .init(title: "Bolus gestoppt", category: .delivery, urgent: true),
        0x0047: .init(title: "Maximale Füllmenge erreicht", category: .delivery, urgent: false),
        0x0048: .init(title: "Maximale Füllmenge erreicht", category: .delivery, urgent: false),
        0x0054: .init(title: "Batterie einsetzen", category: .supplies, urgent: true),
        0x0067: .init(title: "BZ nach Bolus prüfen", category: .reminders, urgent: false),
        0x0068: .init(title: "Pumpenbatterie schwach", category: .supplies, urgent: false),
        0x0069: .init(title: "Reservoir fast leer", category: .supplies, urgent: false),
        0x006A: .init(title: "Reservoir fast leer", category: .supplies, urgent: false),
        0x006C: .init(title: "Persönliche Erinnerung", category: .reminders, urgent: false),
        0x006D: .init(title: "Katheterwechsel-Erinnerung", category: .reminders, urgent: false),
        0x0075: .init(title: "Aktives Insulin gelöscht", category: .other, urgent: false),
        0x0307: .init(title: "Jetzt kalibrieren", category: .calibration, urgent: false),
        0x0308: .init(title: "Kalibrierung nicht akzeptiert", category: .calibration, urgent: false),
        0x0309: .init(title: "Sensor wechseln", category: .sensor, urgent: false),
        0x030A: .init(title: "Sensor wechseln", category: .sensor, urgent: false),
        0x030C: .init(title: "Sensorsignal verloren", category: .sensor, urgent: false),
        0x0312: .init(title: "Keine Kalibrierung erfolgt", category: .calibration, urgent: false),
        0x0315: .init(title: "Sensor wechseln", category: .sensor, urgent: false),
        0x031E: .init(title: "Sensor verbunden", category: .sensor, urgent: false),
        0x0321: .init(title: "Sensorfehler", category: .sensor, urgent: false),
        0x0322: .init(title: "Niedriger SG-Wert", category: .glucose, urgent: false),
        0x0323: .init(title: "Abschaltung bei Tief", category: .glucose, urgent: true),
        0x0325: .init(title: "Alarm vor Tief", category: .glucose, urgent: false),
        0x0327: .init(title: "Basalabgabe fortgesetzt", category: .glucose, urgent: false),
        0x0329: .init(title: "Abschaltung bei Grenzwert", category: .glucose, urgent: true),
        0x032A: .init(title: "Abschaltung vor Tief", category: .glucose, urgent: false),
        0x032B: .init(title: "Abschaltung vor Tief", category: .glucose, urgent: false),
        0x032E: .init(title: "Abschaltung bei Tief: Zeit abgelaufen", category: .glucose, urgent: true),
        0x032F: .init(title: "Manuelle Fortsetzung", category: .glucose, urgent: false),
        0x0330: .init(title: "Hoher SG-Wert", category: .glucose, urgent: false),
        0x0331: .init(title: "Hoher SG-Wert", category: .glucose, urgent: false),
        0x0333: .init(title: "SmartGuard beendet: hoher SG", category: .smartGuard, urgent: false),
        0x0334: .init(title: "SmartGuard beendet", category: .smartGuard, urgent: false),
        0x0335: .init(title: "SmartGuard: minimale Abgabe", category: .smartGuard, urgent: false),
        0x0336: .init(title: "SmartGuard: maximale Abgabe", category: .smartGuard, urgent: false),
        0x033A: .init(title: "SmartGuard aus", category: .smartGuard, urgent: false),
        0x033B: .init(title: "Sehr niedriger SG-Wert", category: .glucose, urgent: true),
        0x0341: .init(title: "SmartGuard: Bolus empfohlen", category: .smartGuard, urgent: false),
        0x0344: .init(title: "Seit 3 Stunden hoch", category: .glucose, urgent: false),
        0x0345: .init(title: "Kalibrierung empfohlen", category: .calibration, urgent: false),
        0x034B: .init(title: "Erste Kalibrierung erfolgreich", category: .calibration, urgent: false),
        0x034C: .init(title: "Frühe Kalibrierung", category: .calibration, urgent: false),
        0x0365: .init(title: "Kalibrier-Erinnerung", category: .calibration, urgent: false),
    ]
}
