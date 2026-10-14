// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation
import MiniMedKit

/// Build-time configuration embedded by Scripts/embed-local-config.sh.
struct AppConfig {
    let devGuard: DevModeGuard
    let keyDatabase: KeyDatabase?
    let keyDatabaseError: String?

    static func load(bundle: Bundle = .main) -> AppConfig {
        var devMode = true
        var serial = ""
        if let url = bundle.url(forResource: "DevConfig", withExtension: "plist"),
           let dict = NSDictionary(contentsOf: url) as? [String: Any] {
            devMode = dict["DEV_MODE"] as? Bool ?? true
            serial = dict["TEST_PUMP_SERIAL"] as? String ?? ""
        }

        var db: KeyDatabase?
        var dbError: String?
        if let url = bundle.url(forResource: "mobile-pump.keydb", withExtension: "hex"),
           let hex = try? String(contentsOf: url, encoding: .utf8) {
            do { db = try KeyDatabase(hex: hex) } catch { dbError = "Schlüsseldatenbank ungültig: \(error)" }
        } else {
            dbError = "Schlüsseldatenbank fehlt im App-Bundle (siehe docs/setup-ios.md)."
        }
        return AppConfig(devGuard: DevModeGuard(devMode: devMode, testPumpSerial: serial),
                         keyDatabase: db, keyDatabaseError: dbError)
    }
}
