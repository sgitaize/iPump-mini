// SPDX-License-Identifier: GPL-3.0-or-later
// Demo mode: simulated values without a pump (App Review, trying the app, screenshots).
//
// In demo mode the app does not use Bluetooth, does not save or upload data and does not
// evaluate alarms. Real data on disk stays untouched and is back after leaving demo mode
// (takes effect on the next app start).
import Foundation

enum DemoMode {
    static let key = "demoMode"

    /// Persisted choice. Read once at launch by `AppModel`; changing it takes effect on
    /// the next start, except `enterNow` on a device without a paired pump.
    static var isOn: Bool {
        get {
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("-demoData") { return true }
            #endif
            return UserDefaults.standard.bool(forKey: key)
        }
        set { UserDefaults.standard.set(newValue, forKey: key) }
    }
}
