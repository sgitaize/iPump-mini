// SPDX-License-Identifier: GPL-3.0-or-later
// Glucose and pump alarms as local notifications, with snooze like common CGM apps.
//
// Critical alerts (sound through mute switch and Focus) need an entitlement Apple grants
// on request. Without it, urgent alarms are sent as time-sensitive notifications.
import Foundation
import MiniMedKit
import UserNotifications

enum GlucoseAlarmKind: String, CaseIterable, Codable, Identifiable {
    case urgentLow, low, high, fallingFast, risingFast

    var id: String { rawValue }

    var title: String {
        switch self {
        case .urgentLow: "Dringend niedrig"
        case .low: "Niedrig"
        case .high: "Hoch"
        case .fallingFast: "Schnell fallend"
        case .risingFast: "Schnell steigend"
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
            case .standard: "Standard"
            case .urgentOnly: "Nur dringend"
            case .all: "Alle"
            }
        }
        var detail: String {
            switch self {
            case .standard: "Dringend niedrig, niedrig, hoch, keine Daten; Pumpe: Abgabe, Reservoir/Batterie, Sensor, Kalibrierung, SmartGuard"
            case .urgentOnly: "Nur dringend niedrig, keine Daten und Probleme mit der Insulinabgabe"
            case .all: "Alle Glukose-Alarme inkl. schneller Änderungen und alle Pumpenmeldungen"
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
        ("SNOOZE_15", 15, "15 min stumm"), ("SNOOZE_30", 30, "30 min stumm"), ("SNOOZE_60", 60, "1 h stumm"),
    ]

    @Published var config: AlarmConfig {
        didSet { save(config, "alarmConfig"); Watchdog.configure(enabled: config.noDataEnabled, minutes: config.noDataMinutes) }
    }
    /// Global mute for all alarms except "urgent low".
    @Published private(set) var mutedUntil: Date?
    @Published private(set) var snoozedUntil: [String: Date] = [:]
    @Published private(set) var criticalAvailable = false
    /// Needs the time-sensitive entitlement (not offered to free personal teams).
    @Published private(set) var timeSensitiveAvailable = false

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
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge, .criticalAlert]) { _, _ in
            UNUserNotificationCenter.current().getNotificationSettings { settings in
                let critical = settings.criticalAlertSetting == .enabled
                let timeSensitive = settings.timeSensitiveSetting == .enabled
                Task { @MainActor in
                    self.criticalAvailable = critical
                    self.timeSensitiveAvailable = timeSensitive
                }
            }
        }
    }

    func applyPreset(_ p: AlarmConfig.Preset) { config = AlarmConfig.preset(p) }

    // MARK: Glucose

    func evaluate(_ reading: GlucoseReading, now: Date = Date()) {
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
                ? "\(reading.mgdl) mg/dL, \(String(format: "%+.1f", reading.trendMgdlPerMin ?? 0)) mg/dL pro Minute"
                : "\(reading.mgdl) mg/dL (\(String(format: "%.1f", g / 18)) mmol/L)"
            fire(key: kind.rawValue, title: kind.title, body: body, urgent: kind == .urgentLow || kind == .low,
                 critical: kind == .urgentLow, repeatMinutes: rule.repeatMinutes, now: now)
        }
    }

    // MARK: Pump

    func pumpAlarm(id: UInt16, type: UInt16, status: UInt8, date: Date, now: Date = Date()) {
        guard status == 0x33, now.timeIntervalSince(date) < 30 * 60, !seenPumpAlarms.contains(id) else { return }
        seenPumpAlarms.append(id)
        if seenPumpAlarms.count > 200 { seenPumpAlarms.removeFirst(seenPumpAlarms.count - 200) }
        save(seenPumpAlarms, "alarmSeenPump")
        let info = PumpAlarms.info(for: type)
        log?.add("Pumpenmeldung: \(info.title) (\(info.category.title))")
        guard config.pump[info.category] == true else { return }
        fire(key: "pump.\(id)", title: "Pumpe: \(info.title)", body: "Meldung der Pumpe um \(date.formatted(date: .omitted, time: .shortened)). Bitte an der Pumpe prüfen.",
             urgent: info.urgent, critical: info.urgent, repeatMinutes: 0, now: now)
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
        post(id: "alarm.test", key: "test", title: "Test-Alarm", body: "So sieht ein Alarm von iPump-mini aus.", urgent: true, critical: true)
    }

    // MARK: Internals

    private func fire(key: String, title: String, body: String, urgent: Bool, critical: Bool, repeatMinutes: Int, now: Date) {
        if let until = snoozedUntil[key], until > now { return }
        if !critical, let until = mutedUntil, until > now { return }
        if let last = lastFired[key] {
            if repeatMinutes == 0 { return }
            if now.timeIntervalSince(last) < Double(repeatMinutes) * 60 - 30 { return }
        }
        lastFired[key] = now
        save(lastFired, "alarmLastFired")
        post(id: "alarm.\(key)", key: key, title: title, body: body, urgent: urgent, critical: critical)
        log?.add("Alarm: \(title) – \(body)", .warning)
    }

    private func clear(_ key: String) {
        guard lastFired.removeValue(forKey: key) != nil else { return }
        save(lastFired, "alarmLastFired")
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: ["alarm.\(key)"])
    }

    private func post(id: String, key: String, title: String, body: String, urgent: Bool, critical: Bool) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.categoryIdentifier = Self.categoryID
        content.userInfo = ["alarmKey": key]
        if critical && criticalAvailable {
            content.sound = .defaultCriticalSound(withAudioVolume: 1.0)
            content.interruptionLevel = .critical
        } else {
            content.sound = .default
            content.interruptionLevel = urgent ? .timeSensitive : .active
        }
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
