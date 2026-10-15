// SPDX-License-Identifier: GPL-3.0-or-later
// Feeds the widgets (App Group file + timeline reload) and the Live Activity.
import ActivityKit
import Foundation
import MiniMedKit
import WidgetKit

@MainActor
enum WidgetBridge {
    static var log: EventLog?

    static var liveActivityEnabled: Bool {
        get { UserDefaults.standard.object(forKey: "liveActivity") as? Bool ?? true }
        set {
            UserDefaults.standard.set(newValue, forKey: "liveActivity")
            if !newValue { endLiveActivities() }
        }
    }

    /// Called for every new sensor value (also in the background, woken by the pump).
    static func update(store: DataStore) {
        let snapshot = makeSnapshot(store: store)
        SharedStore.write(snapshot)
        WidgetCenter.shared.reloadAllTimelines()
        updateLiveActivity(snapshot)
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

    /// Live Activities can only be started while the app is in the foreground.
    static func appBecameActive(store: DataStore) {
        guard liveActivityEnabled, ActivityAuthorizationInfo().areActivitiesEnabled,
              let state = state(for: store) else { return }
        if Activity<GlucoseActivityAttributes>.activities.isEmpty {
            do {
                _ = try Activity.request(attributes: GlucoseActivityAttributes(),
                                         content: ActivityContent(state: state, staleDate: state.date.addingTimeInterval(15 * 60)))
                log?.add("Live-Aktivität gestartet")
            } catch {
                log?.add("Live-Aktivität nicht gestartet: \(error.localizedDescription)", .warning)
            }
        } else {
            update(store: store)
        }
    }

    private static func state(for store: DataStore) -> GlucoseActivityAttributes.ContentState? {
        guard let r = store.latest else { return nil }
        let readings = store.readings
        var delta: Int?
        if readings.count >= 2, r.date.timeIntervalSince(readings[readings.count - 2].date) < 15 * 60 {
            delta = r.mgdl - readings[readings.count - 2].mgdl
        }
        return .init(mgdl: r.mgdl, trendRate: r.trendMgdlPerMin, delta: delta, date: r.date, iob: store.snapshot.iob?.units)
    }

    private static func updateLiveActivity(_ s: WidgetSnapshot) {
        guard liveActivityEnabled, let latest = s.latest else { return }
        let state = GlucoseActivityAttributes.ContentState(mgdl: latest.mgdl, trendRate: s.trendRate, delta: s.delta, date: latest.date, iob: s.iob)
        for activity in Activity<GlucoseActivityAttributes>.activities {
            Task { await activity.update(ActivityContent(state: state, staleDate: latest.date.addingTimeInterval(15 * 60))) }
        }
    }

    private static func endLiveActivities() {
        for activity in Activity<GlucoseActivityAttributes>.activities {
            Task { await activity.end(nil, dismissalPolicy: .immediate) }
        }
    }
}
