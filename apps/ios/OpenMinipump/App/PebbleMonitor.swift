// SPDX-License-Identifier: GPL-3.0-or-later
// Optional: warns when a Pebble watch face stopped fetching values from the local API.
import Foundation
import UserNotifications

@MainActor
enum PebbleMonitor {
    static let enabledKey = "pebbleMonitor"
    static let minutesKey = "pebbleMonitorMinutes"
    private static let lastRequestKey = "pebbleLastRequest"
    private static let sinceKey = "pebbleMonitorSince"
    private static let notifiedKey = "pebbleMonitorNotified"
    private static let notificationID = "pebble.stale"

    static var enabled: Bool {
        get { UserDefaults.standard.bool(forKey: enabledKey) }
        set {
            UserDefaults.standard.set(newValue, forKey: enabledKey)
            // The time limit counts from switching on if no request came yet.
            UserDefaults.standard.set(Date(), forKey: sinceKey)
            UserDefaults.standard.set(false, forKey: notifiedKey)
        }
    }

    static var minutes: Int {
        get { (UserDefaults.standard.object(forKey: minutesKey) as? Int) ?? 20 }
        set { UserDefaults.standard.set(newValue, forKey: minutesKey) }
    }

    static var lastRequest: Date? { UserDefaults.standard.object(forKey: lastRequestKey) as? Date }

    /// Called for every /pebble request (any client of the local API).
    static func pebbleRequested() {
        UserDefaults.standard.set(Date(), forKey: lastRequestKey)
        if UserDefaults.standard.bool(forKey: notifiedKey) {
            UserDefaults.standard.set(false, forKey: notifiedKey)
            UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: [notificationID])
        }
    }

    /// Called on every pump wake-up (also in the background): one notification per outage.
    static func check(now: Date = Date()) {
        guard enabled, !UserDefaults.standard.bool(forKey: notifiedKey) else { return }
        let since = UserDefaults.standard.object(forKey: sinceKey) as? Date ?? now
        let reference = max(lastRequest ?? since, since)
        let silent = now.timeIntervalSince(reference)
        guard silent >= Double(minutes * 60) else { return }
        UserDefaults.standard.set(true, forKey: notifiedKey)
        let content = UNMutableNotificationContent()
        content.title = L10n.tr("Pebble bekommt keine Werte")
        content.body = L10n.tr("Seit %d Minuten hat deine Pebble keine Werte von iPump-mini abgerufen. Pebble-App und Bluetooth prüfen, ggf. iPump-mini einmal öffnen.", Int(silent / 60))
        content.sound = .default
        content.interruptionLevel = .timeSensitive
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: notificationID, content: content, trigger: nil))
    }
}
