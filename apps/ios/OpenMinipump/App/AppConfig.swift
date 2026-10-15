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
            do { db = try KeyDatabase(hex: hex); source = .bundle } catch { dbError = L10n.tr("Schlüsseldatenbank ungültig: %@", "\(error)") }
        } else if let hex = KeyImport.stored(), let imported = try? KeyImport.validate(hex) {
            db = imported
            source = .imported
        } else {
            dbError = L10n.tr("Schlüsseldatenbank fehlt. Einstellungen › Pumpe › Schlüsseldatenbank.")
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
        guard isMobilePump(db) else { throw KeyImportError.wrongDatabase }
        return db
    }

    static func isMobilePump(_ db: KeyDatabase) -> Bool {
        db.localDeviceType == .mobileApplication && db.remoteDevices[.insulinPump] != nil
    }

    static func save(_ hex: String) throws -> KeyDatabase {
        let clean = hex.filter { !$0.isWhitespace }
        let db = try validate(clean)
        Keychain.set(clean, for: account)
        return db
    }

    static func remove() { Keychain.set("", for: account) }

    /// Public documentation of OpenMinimed that lists the dumped key databases.
    static let openMinimedURL = URL(string: "https://raw.githubusercontent.com/OpenMinimed/Documentation/main/key_databases.md")!
    static let openMinimedPage = URL(string: "https://github.com/OpenMinimed/Documentation/blob/main/key_databases.md")!

    /// Finds the matching database in plain hex or a page like key_databases.md.
    static func extract(from text: String) -> String? {
        KeyDatabase.findHex(in: text, accept: isMobilePump)
    }

    /// Downloads a page or file, extracts the database and stores it.
    static func load(from url: URL) async throws -> KeyDatabase {
        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw KeyImportError.http(http.statusCode)
        }
        guard let text = String(data: data, encoding: .utf8), let hex = extract(from: text) else {
            throw KeyImportError.notFound
        }
        return try save(hex)
    }
}

enum KeyImportError: LocalizedError {
    case wrongDatabase, notFound, http(Int)
    var errorDescription: String? {
        switch self {
        case .wrongDatabase: return L10n.tr("Das ist nicht die Datenbank „Mobile Application ↔ Insulin Pump“.")
        case .notFound: return L10n.tr("Unter dieser Adresse wurde keine passende Datenbank gefunden.")
        case .http(let code): return L10n.tr("Server antwortet mit Fehler %d.", code)
        }
    }
}
