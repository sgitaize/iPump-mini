// SPDX-License-Identifier: GPL-3.0-or-later
// Local notifications that remind the user to reopen the app.
//
// iOS does not run any code after the user swipes the app away, so we use a
// dead man's switch: after every successful pump update a notification is scheduled
// 20 minutes ahead and replaced on the next update. If the app was closed (or the
// pump is out of range), the notification fires. In addition we try to post an
// immediate one in applicationWillTerminate, which iOS calls only sometimes.
import Foundation
import UserNotifications

enum Watchdog {
    static let delay: TimeInterval = 20 * 60
    private static let staleID = "openminipump.stale"
    private static let terminatedID = "openminipump.terminated"

    static var enabled: Bool {
        get { UserDefaults.standard.object(forKey: "watchdogEnabled") as? Bool ?? true }
        set {
            UserDefaults.standard.set(newValue, forKey: "watchdogEnabled")
            if !newValue { UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [staleID]) }
        }
    }

    static func requestAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    /// Called after every successful pump update.
    static func arm() {
        guard enabled else { return }
        let content = UNMutableNotificationContent()
        content.title = "Keine Pumpendaten seit 20 Minuten"
        content.body = "Ist openMinipump noch geöffnet und die Pumpe in Reichweite? Tippe hier, um die App zu öffnen."
        content.sound = .default
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: delay, repeats: false)
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [staleID])
        center.add(UNNotificationRequest(identifier: staleID, content: content, trigger: trigger))
    }

    /// Called from applicationWillTerminate (best effort).
    static func appTerminated() {
        guard enabled else { return }
        let content = UNMutableNotificationContent()
        content.title = "openMinipump wurde beendet"
        content.body = "Ohne laufende App kommen keine Werte von der Pumpe. Tippe hier, um sie wieder zu öffnen."
        content.sound = .default
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 2, repeats: false)
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: terminatedID, content: content, trigger: trigger))
    }

    static func appOpened() {
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: [staleID, terminatedID])
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [terminatedID])
    }
}
