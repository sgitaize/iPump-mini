// SPDX-License-Identifier: GPL-3.0-or-later
// Feeds the widgets (App Group file + timeline reload) and the Live Activity.
import ActivityKit
import Foundation
import MiniMedKit
import UIKit
import UserNotifications
import WidgetKit

@MainActor
enum WidgetBridge {
    static var log: EventLog?

    static var liveActivityEnabled: Bool {
        get { UserDefaults.standard.object(forKey: "liveActivity") as? Bool ?? true }
        set {
            UserDefaults.standard.set(newValue, forKey: "liveActivity")
            if !newValue { endLiveActivities(); cancelExpiryReminder() }
        }
    }

    /// Called for every new sensor value (also in the background, woken by the pump).
    static func update(store: DataStore) {
        let snapshot = makeSnapshot(store: store)
        SharedStore.write(snapshot)
        if let latest = snapshot.latest, shouldReloadWidgets(latest) {
            WidgetCenter.shared.reloadTimelines(ofKind: "glucose")
            lastWidgetReload = (latest.mgdl, Date())
        }
        updateLiveActivity(snapshot)
    }

    /// Home and lock screen widgets get only ~40–70 background reloads per day; reloading
    /// on every 5-minute value (288/day) used the budget up by midday and the widget then
    /// updated only sporadically. So in the background a reload is spent only when it
    /// matters: lows always, range changes, changes of ≥ 10 mg/dL, otherwise every 20 min.
    /// In the foreground reloads are free. The Live Activity has no such budget.
    private static var lastWidgetReload: (mgdl: Int, at: Date)? {
        get {
            let d = UserDefaults.standard
            guard let at = d.object(forKey: "widgetReloadAt") as? Date else { return nil }
            return (d.integer(forKey: "widgetReloadMgdl"), at)
        }
        set {
            UserDefaults.standard.set(newValue?.mgdl, forKey: "widgetReloadMgdl")
            UserDefaults.standard.set(newValue?.at, forKey: "widgetReloadAt")
        }
    }

    private static func shouldReloadWidgets(_ latest: WidgetSnapshot.Point) -> Bool {
        if UIApplication.shared.applicationState == .active { return true }
        guard let last = lastWidgetReload else { return true }
        let low = Prefs.low, high = Prefs.high
        func range(_ v: Int) -> Int { v < low ? 0 : v > high ? 2 : 1 }
        if latest.mgdl < low { return true }
        if range(latest.mgdl) != range(last.mgdl) { return true }
        if abs(latest.mgdl - last.mgdl) >= 10 { return true }
        return Date().timeIntervalSince(last.at) >= 20 * 60
    }

    static func makeSnapshot(store: DataStore) -> WidgetSnapshot {
        let from = Date().addingTimeInterval(-6 * 3600)
        let points = store.readings.filter { $0.date >= from }.map { WidgetSnapshot.Point(date: $0.date, mgdl: $0.mgdl) }
        let s = store.snapshot
        let mode: String? = switch s.algorithm?.shieldState {
        case .autoBasal: "smartguard"
        case .safeBasal: "safe"
        case .openLoop: "manual"
        case nil: nil
        }
        let snapshot = WidgetSnapshot(points: points, trendRate: store.latest?.trendMgdlPerMin,
                                      iob: s.iob?.units, updatedAt: Date(),
                                      reservoir: s.status?.reservoirUnits, pumpBattery: s.pumpBatteryPercent,
                                      mode: mode, sensorEnd: s.sensorEnd)
        return snapshot
    }

    /// iOS ends a Live Activity after 8 hours. The ended activity stays in `activities` (and up to
    /// 4 more hours on the lock screen), so "list is empty" never became true again and no new one
    /// was started (issue #4). Each foreground start therefore replaces ended activities and renews
    /// one that is older than `renewAfter`, so every app visit buys a fresh 8-hour window.
    private static let renewAfter: TimeInterval = 4 * 3600

    private static var activityStartedAt: Date? {
        get { UserDefaults.standard.object(forKey: "liveActivityStartedAt") as? Date }
        set { UserDefaults.standard.set(newValue, forKey: "liveActivityStartedAt") }
    }

    private static var runningActivities: [Activity<GlucoseActivityAttributes>] {
        Activity<GlucoseActivityAttributes>.activities.filter { $0.activityState == .active || $0.activityState == .stale }
    }

    /// Live Activities can only be started while the app is in the foreground.
    static func appBecameActive(store: DataStore) {
        SharedStore.write(makeSnapshot(store: store))
        WidgetCenter.shared.reloadTimelines(ofKind: "glucose")   // free while in the foreground
        guard liveActivityEnabled, ActivityAuthorizationInfo().areActivitiesEnabled,
              let state = state(for: store) else { return }
        let all = Activity<GlucoseActivityAttributes>.activities
        let running = runningActivities
        let expiring = activityStartedAt.map { Date().timeIntervalSince($0) > renewAfter } ?? true
        if running.isEmpty || expiring {
            for activity in all {
                Task { await activity.end(nil, dismissalPolicy: .immediate) }
            }
            startActivity(state, reason: running.isEmpty ? (all.isEmpty ? "gestartet" : "neu gestartet (abgelaufen)") : "erneuert")
        } else {
            update(store: store)
        }
    }

    private static func startActivity(_ state: GlucoseActivityAttributes.ContentState, reason: String) {
        do {
            _ = try Activity.request(attributes: GlucoseActivityAttributes(),
                                     content: ActivityContent(state: state, staleDate: state.date.addingTimeInterval(15 * 60)))
            activityStartedAt = Date()
            UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: [expiryReminderID])
            scheduleExpiryReminder()
            log?.add("Live-Aktivität \(reason)")
        } catch {
            log?.add("Live-Aktivität nicht gestartet: \(error.localizedDescription)", .warning)
        }
    }

    // MARK: Reminder when iOS ends the Live Activity

    /// iOS only lets the app start a Live Activity in the foreground (push-to-start would need an
    /// APNs server). So a local notification is scheduled for the moment iOS ends it (start + 8 h);
    /// tapping it opens the app, which starts a new one. Within the quiet hours it waits until they
    /// end. Normal interruption level: Focus modes such as Sleep or Do Not Disturb hold it back.
    static let expiryReminderID = "liveActivityExpired"
    private static let systemLimit: TimeInterval = 8 * 3600

    static var expiryReminderEnabled: Bool {
        get { UserDefaults.standard.object(forKey: "liveActivityReminder") as? Bool ?? true }
        set {
            UserDefaults.standard.set(newValue, forKey: "liveActivityReminder")
            if newValue { scheduleExpiryReminder() } else { cancelExpiryReminder() }
        }
    }

    /// Quiet hours as hour of day (0–23); equal values mean no quiet hours.
    static var quietFrom: Int {
        get { UserDefaults.standard.object(forKey: "liveActivityQuietFrom") as? Int ?? 22 }
        set { UserDefaults.standard.set(newValue, forKey: "liveActivityQuietFrom"); scheduleExpiryReminder() }
    }
    static var quietTo: Int {
        get { UserDefaults.standard.object(forKey: "liveActivityQuietTo") as? Int ?? 7 }
        set { UserDefaults.standard.set(newValue, forKey: "liveActivityQuietTo"); scheduleExpiryReminder() }
    }

    /// Moves `date` out of the quiet hours (to their end), if it falls into them.
    static func outsideQuietHours(_ date: Date, calendar: Calendar = .current) -> Date {
        let from = quietFrom, to = quietTo
        guard from != to else { return date }
        let hour = calendar.component(.hour, from: date)
        let quiet = from < to ? (hour >= from && hour < to) : (hour >= from || hour < to)
        guard quiet else { return date }
        var end = calendar.date(bySettingHour: to, minute: 0, second: 0, of: date) ?? date
        if end <= date { end = calendar.date(byAdding: .day, value: 1, to: end) ?? date }
        return end
    }

    private static func scheduleExpiryReminder() {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [expiryReminderID])
        guard liveActivityEnabled, expiryReminderEnabled, let start = activityStartedAt else { return }
        let fire = outsideQuietHours(start.addingTimeInterval(systemLimit))
        let interval = fire.timeIntervalSinceNow
        guard interval > 1 else { return }
        let content = UNMutableNotificationContent()
        content.title = L10n.tr("Live-Aktivität abgelaufen")
        content.body = L10n.tr("iOS beendet Live-Aktivitäten nach 8 Stunden. Tippe hier, um sie neu zu starten.")
        content.interruptionLevel = .active
        content.threadIdentifier = expiryReminderID
        let request = UNNotificationRequest(identifier: expiryReminderID, content: content,
                                            trigger: UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false))
        center.add(request)
    }

    private static func cancelExpiryReminder() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [expiryReminderID])
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: [expiryReminderID])
    }

    private static func state(for store: DataStore) -> GlucoseActivityAttributes.ContentState? {
        guard let r = store.latest else { return nil }
        let readings = store.readings
        var delta: Int?
        if readings.count >= 2, r.date.timeIntervalSince(readings[readings.count - 2].date) < 15 * 60 {
            delta = r.mgdl - readings[readings.count - 2].mgdl
        }
        let points = readings.suffix(48).map { WidgetSnapshot.Point(date: $0.date, mgdl: $0.mgdl) }
        return .init(mgdl: r.mgdl, trendRate: r.trendMgdlPerMin, delta: delta, date: r.date, iob: store.snapshot.iob?.units,
                     curve: GlucoseActivityAttributes.curve(from: points, latest: r.date))
    }

    private static func updateLiveActivity(_ s: WidgetSnapshot) {
        guard liveActivityEnabled, let latest = s.latest else { return }
        let state = GlucoseActivityAttributes.ContentState(mgdl: latest.mgdl, trendRate: s.trendRate, delta: s.delta, date: latest.date, iob: s.iob,
                                                                curve: GlucoseActivityAttributes.curve(from: s.points, latest: latest.date))
        let running = runningActivities
        for activity in running {
            Task { await activity.update(ActivityContent(state: state, staleDate: latest.date.addingTimeInterval(15 * 60))) }
        }
        // Ended by iOS while the app runs in the background: try to start a new one. iOS normally
        // refuses this outside the foreground; we try once per ended activity and log the result.
        if running.isEmpty, !Activity<GlucoseActivityAttributes>.activities.isEmpty,
           ActivityAuthorizationInfo().areActivitiesEnabled, backgroundRestartTried != activityStartedAt {
            backgroundRestartTried = activityStartedAt
            for activity in Activity<GlucoseActivityAttributes>.activities {
                Task { await activity.end(nil, dismissalPolicy: .immediate) }
            }
            startActivity(state, reason: "im Hintergrund neu gestartet")
        }
    }

    private static var backgroundRestartTried: Date?

    private static func endLiveActivities() {
        for activity in Activity<GlucoseActivityAttributes>.activities {
            Task { await activity.end(nil, dismissalPolicy: .immediate) }
        }
    }
}
