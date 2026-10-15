// SPDX-License-Identifier: GPL-3.0-or-later
// Glucose and pump alarms as local notifications, with snooze like common CGM apps.
//
// Urgent alarms (urgent low, urgent pump alerts) are time-sensitive notifications: they
// break through Focus modes if the user allows it, but follow the silent switch. Critical
// alerts (through the silent switch) would need an Apple entitlement and are not used.
import Foundation
import MiniMedKit
import UserNotifications

enum GlucoseAlarmKind: String, CaseIterable, Codable, Identifiable {
    case urgentLow, low, high, fallingFast, risingFast

    var id: String { rawValue }

    var title: String {
        switch self {
        case .urgentLow: L10n.tr("Dringend niedrig")
        case .low: L10n.tr("Niedrig")
        case .high: L10n.tr("Hoch")
        case .fallingFast: L10n.tr("Schnell fallend")
        case .risingFast: L10n.tr("Schnell steigend")
        }
    }

    /// Threshold is a glucose value (mg/dL) or a rate (mg/dL per minute).
    var isRate: Bool { self == .fallingFast || self == .risingFast }
}

struct AlarmRule: Codable, Equatable {
    var enabled: Bool
    var threshold: Double
    var snoozeMinutes: Int
    var repeatMinutes: Int
}

struct AlarmConfig: Codable, Equatable {
    var glucose: [GlucoseAlarmKind: AlarmRule]
    var pump: [PumpAlarmCategory: Bool]
    var noDataEnabled: Bool
    var noDataMinutes: Int

    enum Preset: String, CaseIterable, Identifiable {
        case standard, urgentOnly, all
        var id: String { rawValue }
        var title: String {
            switch self {
            case .standard: L10n.tr("Standard")
            case .urgentOnly: L10n.tr("Nur dringend")
            case .all: L10n.tr("Alle")
            }
        }
        var detail: String {
            switch self {
            case .standard: L10n.tr("Dringend niedrig, niedrig, hoch, keine Daten; Pumpe: Abgabe, Reservoir/Batterie, Sensor, Kalibrierung, SmartGuard")
            case .urgentOnly: L10n.tr("Nur dringend niedrig, keine Daten und Probleme mit der Insulinabgabe")
            case .all: L10n.tr("Alle Glukose-Alarme inkl. schneller Änderungen und alle Pumpenmeldungen")
            }
        }
    }

    static func preset(_ p: Preset) -> AlarmConfig {
        var glucose: [GlucoseAlarmKind: AlarmRule] = [
            .urgentLow: AlarmRule(enabled: true, threshold: 55, snoozeMinutes: 15, repeatMinutes: 5),
            .low: AlarmRule(enabled: true, threshold: 70, snoozeMinutes: 30, repeatMinutes: 15),
            .high: AlarmRule(enabled: true, threshold: 250, snoozeMinutes: 60, repeatMinutes: 60),
            .fallingFast: AlarmRule(enabled: false, threshold: 2, snoozeMinutes: 30, repeatMinutes: 30),
            .risingFast: AlarmRule(enabled: false, threshold: 2, snoozeMinutes: 30, repeatMinutes: 30),
        ]
        var pump = Dictionary(uniqueKeysWithValues: PumpAlarmCategory.allCases.map { ($0, false) })
        switch p {
        case .standard:
            for c in [PumpAlarmCategory.delivery, .supplies, .sensor, .calibration, .smartGuard] { pump[c] = true }
        case .urgentOnly:
            glucose[.low]?.enabled = false
            glucose[.high]?.enabled = false
            pump[.delivery] = true
        case .all:
            for k in GlucoseAlarmKind.allCases { glucose[k]?.enabled = true }
            for c in PumpAlarmCategory.allCases { pump[c] = true }
        }
        return AlarmConfig(glucose: glucose, pump: pump, noDataEnabled: true, noDataMinutes: 20)
    }
}

@MainActor
final class AlarmEngine: ObservableObject {
    static let shared = AlarmEngine()

    static let categoryID = "OMP_ALARM"
    static let snoozeActions: [(id: String, minutes: Int, title: String)] = [
        ("SNOOZE_15", 15, L10n.tr("15 min stumm")), ("SNOOZE_30", 30, L10n.tr("30 min stumm")), ("SNOOZE_60", 60, L10n.tr("1 h stumm")),
    ]

    @Published var config: AlarmConfig {
        didSet { save(config, "alarmConfig"); Watchdog.configure(enabled: config.noDataEnabled, minutes: config.noDataMinutes) }
    }
    /// Global mute for all alarms except "urgent low".
    @Published private(set) var mutedUntil: Date?
    @Published private(set) var snoozedUntil: [String: Date] = [:]
    /// Needs the time-sensitive entitlement (paid developer team) and the user's permission.
    @Published private(set) var timeSensitiveAvailable = false
    /// Notifications allowed at all.
    @Published private(set) var notificationsAllowed = false

    private var lastFired: [String: Date] = [:]
    private var seenPumpAlarms: [UInt16] = []
    var log: EventLog?

    private init() {
        config = Self.load("alarmConfig") ?? AlarmConfig.preset(.standard)
        mutedUntil = Self.load("alarmMutedUntil")
        snoozedUntil = Self.load("alarmSnoozes") ?? [:]
        lastFired = Self.load("alarmLastFired") ?? [:]
        seenPumpAlarms = Self.load("alarmSeenPump") ?? []
    }

    // MARK: Setup

    func registerCategories() {
        let actions = Self.snoozeActions.map { UNNotificationAction(identifier: $0.id, title: $0.title, options: []) }
        let category = UNNotificationCategory(identifier: Self.categoryID, actions: actions, intentIdentifiers: [], options: [])
        UNUserNotificationCenter.current().setNotificationCategories([category])
    }

    func requestAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in
            Task { @MainActor in self.refreshSettings() }
        }
    }

    /// Reads the current notification settings (the user may change them in iOS Settings).
    func refreshSettings() {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            let allowed = settings.authorizationStatus == .authorized
            let timeSensitive = settings.timeSensitiveSetting == .enabled
            Task { @MainActor in
                self.notificationsAllowed = allowed
                self.timeSensitiveAvailable = timeSensitive
            }
        }
    }

    func applyPreset(_ p: AlarmConfig.Preset) { config = AlarmConfig.preset(p) }

    // MARK: Glucose

    func evaluate(_ reading: GlucoseReading, now: Date = Date()) {
        guard !DemoMode.isOn else { return }   // no alarms for simulated values
        guard now.timeIntervalSince(reading.date) < 10 * 60 else { return }
        let g = Double(reading.mgdl)
        let urgent = config.glucose[.urgentLow]
        let active: [GlucoseAlarmKind: Bool] = [
            .urgentLow: g <= (urgent?.threshold ?? 55),
            .low: g <= (config.glucose[.low]?.threshold ?? 70) && g > (urgent?.enabled == true ? urgent!.threshold : 0),
            .high: g >= (config.glucose[.high]?.threshold ?? 250),
            .fallingFast: (reading.trendMgdlPerMin ?? 0) <= -(config.glucose[.fallingFast]?.threshold ?? 2),
            .risingFast: (reading.trendMgdlPerMin ?? 0) >= (config.glucose[.risingFast]?.threshold ?? 2),
        ]
        for kind in GlucoseAlarmKind.allCases {
            guard let rule = config.glucose[kind], rule.enabled, active[kind] == true else {
                clear(kind.rawValue)
                continue
            }
            let body: String = kind.isRate
                ? L10n.tr("%d mg/dL, %@ mg/dL pro Minute", reading.mgdl, String(format: "%+.1f", reading.trendMgdlPerMin ?? 0))
                : L10n.tr("%d mg/dL (%@ mmol/L)", reading.mgdl, String(format: "%.1f", g / 18.0182))
            fire(key: kind.rawValue, title: kind.title, body: body, urgent: kind == .urgentLow || kind == .low,
                 ignoresMute: kind == .urgentLow, repeatMinutes: rule.repeatMinutes, now: now)
        }
    }

    // MARK: Pump

    func pumpAlarm(id: UInt16, type: UInt16, status: UInt8, date: Date, now: Date = Date()) {
        log?.add(String(format: "Alarm-Eintrag der Pumpe: id %d, Typ 0x%04X, Status 0x%02X, %@", Int(id), Int(type), Int(status),
                        date.formatted(date: .omitted, time: .shortened)))
        guard status == 0x33, now.timeIntervalSince(date) < 30 * 60, !seenPumpAlarms.contains(id) else { return }
        seenPumpAlarms.append(id)
        if seenPumpAlarms.count > 200 { seenPumpAlarms.removeFirst(seenPumpAlarms.count - 200) }
        save(seenPumpAlarms, "alarmSeenPump")
        let info = PumpAlarms.info(for: type)
        log?.add("Pumpenmeldung: \(info.title) (\(info.category.title))")
        guard config.pump[info.category] == true else { return }
        fire(key: "pump.\(id)", title: L10n.tr("Pumpe: %@", L10n.tr(info.title)),
             body: L10n.tr("Meldung der Pumpe um %@. Bitte an der Pumpe prüfen.", date.formatted(date: .omitted, time: .shortened)),
             urgent: info.urgent, ignoresMute: info.urgent, repeatMinutes: 0, now: now)
    }

    // MARK: Sensor

    /// Sensor state from the pump status (read every update). One notification whenever it
    /// changes into a problem state (e.g. "change sensor", "no signal"); cleared when ok.
    /// Uses the pump alert category "Sensor".
    func sensorStatus(_ status: PumpStatus, now: Date = Date()) {
        guard !DemoMode.isOn else { return }
        let state = Int(status.sensorMessageState) | (status.sensorSignalLost ? 0x100 : 0) | (status.sensorOn ? 0 : 0x200)
        let previous = UserDefaults.standard.object(forKey: "alarmSensorState") as? Int
        guard state != previous else { return }
        UserDefaults.standard.set(state, forKey: "alarmSensorState")
        let text = Self.sensorText(status)
        log?.add("Sensorstatus: \(text)")
        clear("sensor")
        guard !status.sensorOK, config.pump[.sensor] == true else { return }
        fire(key: "sensor", title: L10n.tr("Sensor: %@", L10n.tr(text)),
             body: L10n.tr("Die Pumpe meldet ein Problem mit dem Sensor. Bitte an der Pumpe prüfen."),
             urgent: false, ignoresMute: false, repeatMinutes: 0, now: now)
    }

    /// German source text of the sensor state (localised with L10n.tr).
    static func sensorText(_ status: PumpStatus) -> String {
        if !status.sensorOn { return "Kein Sensor aktiv" }
        if status.sensorSignalLost { return "Sensorsignal verloren" }
        return status.sensorMessage
    }

    // MARK: Snooze

    func snooze(key: String, minutes: Int) {
        snoozedUntil[key] = Date().addingTimeInterval(Double(minutes) * 60)
        save(snoozedUntil, "alarmSnoozes")
        log?.add("Alarm \(key) für \(minutes) min stummgeschaltet")
    }

    func muteAll(minutes: Int?) {
        mutedUntil = minutes.map { Date().addingTimeInterval(Double($0) * 60) }
        save(mutedUntil, "alarmMutedUntil")
    }

    func sendTest() {
        post(id: "alarm.test", key: "test", title: L10n.tr("Test-Alarm"), body: L10n.tr("So sieht ein Alarm von iPump-mini aus."), urgent: true)
    }

    // MARK: Internals

    /// `ignoresMute`: urgent low and urgent pump alerts are not silenced by the global mute.
    private func fire(key: String, title: String, body: String, urgent: Bool, ignoresMute: Bool, repeatMinutes: Int, now: Date) {
        if let until = snoozedUntil[key], until > now { return }
        if !ignoresMute, let until = mutedUntil, until > now { return }
        if let last = lastFired[key] {
            if repeatMinutes == 0 { return }
            if now.timeIntervalSince(last) < Double(repeatMinutes) * 60 - 30 { return }
        }
        lastFired[key] = now
        save(lastFired, "alarmLastFired")
        post(id: "alarm.\(key)", key: key, title: title, body: body, urgent: urgent)
        log?.add("Alarm: \(title) – \(body)", .warning)
    }

    private func clear(_ key: String) {
        guard lastFired.removeValue(forKey: key) != nil else { return }
        save(lastFired, "alarmLastFired")
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: ["alarm.\(key)"])
    }

    private func post(id: String, key: String, title: String, body: String, urgent: Bool) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.categoryIdentifier = Self.categoryID
        content.userInfo = ["alarmKey": key]
        content.sound = .default
        content.interruptionLevel = urgent ? .timeSensitive : .active
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: id, content: content, trigger: nil))
    }

    private func save<T: Encodable>(_ value: T, _ key: String) {
        UserDefaults.standard.set(try? JSONEncoder().encode(value), forKey: key)
    }

    private static func load<T: Decodable>(_ key: String) -> T? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }
}
