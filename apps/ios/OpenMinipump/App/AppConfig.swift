// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation
import MiniMedKit

/// Build-time configuration embedded by Scripts/embed-local-config.sh.
struct AppConfig {
    let devGuard: DevModeGuard
    let keyDatabase: KeyDatabase?
    let keyDatabaseError: String?
    /// Where the key database came from (bundle for own builds, import for public builds).
    let keyDatabaseSource: KeySource

    enum KeySource { case bundle, imported, missing }

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
        var source = KeySource.missing
        if let url = bundle.url(forResource: "mobile-pump.keydb", withExtension: "hex"),
           let hex = try? String(contentsOf: url, encoding: .utf8) {
            do { db = try KeyDatabase(hex: hex); source = .bundle } catch { dbError = "Schlüsseldatenbank ungültig: \(error)" }
        } else if let hex = KeyImport.stored(), let imported = try? KeyImport.validate(hex) {
            db = imported
            source = .imported
        } else {
            dbError = "Schlüsseldatenbank fehlt. Einstellungen › Pumpe › Schlüsseldatenbank."
        }
        return AppConfig(devGuard: DevModeGuard(devMode: devMode, testPumpSerial: serial),
                         keyDatabase: db, keyDatabaseError: dbError, keyDatabaseSource: source)
    }
}

/// Key database imported by the user (public builds ship without it). Stored in the keychain.
enum KeyImport {
    private static let account = "sakeKeyDatabase"

    static func stored() -> String? { Keychain.get(account) }

    /// Checks CRC and that it is the "Mobile Application ↔ Insulin Pump" database.
    static func validate(_ hex: String) throws -> KeyDatabase {
        let db = try KeyDatabase(hex: hex)
        guard db.localDeviceType == .mobileApplication, db.remoteDevices[.insulinPump] != nil else {
            throw KeyImportError.wrongDatabase
        }
        return db
    }

    static func save(_ hex: String) throws -> KeyDatabase {
        let clean = hex.filter { !$0.isWhitespace }
        let db = try validate(clean)
        Keychain.set(clean, for: account)
        return db
    }

    static func remove() { Keychain.set("", for: account) }
}

enum KeyImportError: LocalizedError {
    case wrongDatabase
    var errorDescription: String? { "Das ist nicht die Datenbank „Mobile Application ↔ Insulin Pump“." }
}
