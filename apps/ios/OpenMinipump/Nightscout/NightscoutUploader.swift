// SPDX-License-Identifier: GPL-3.0-or-later
// Optional upload to the user's own Nightscout (API v1).
//
// Runs whenever new pump data arrives. Because the pump wakes the app via Bluetooth
// about every 5 minutes, this also works in the background, unlike the local API.
import CryptoKit
import Foundation
import MiniMedKit
import Security
import UIKit

enum Keychain {
    private static let service = "de.sgitaize.openminipump"

    static func get(_ account: String) -> String? {
        var item: CFTypeRef?
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
            kSecAttrAccount as String: account, kSecReturnData as String: true,
        ]
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess, let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func set(_ value: String, for account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
        guard !value.isEmpty else { return }
        var add = query
        add[kSecValueData as String] = Data(value.utf8)
        // Readable after first unlock, so uploads work while the phone is locked.
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(add as CFDictionary, nil)
    }
}

@MainActor
final class NightscoutUploader: ObservableObject {
    @Published var enabled = UserDefaults.standard.bool(forKey: "nsEnabled") {
        didSet { UserDefaults.standard.set(enabled, forKey: "nsEnabled") }
    }
    @Published var url = UserDefaults.standard.string(forKey: "nsURL") ?? "" {
        didSet { UserDefaults.standard.set(url, forKey: "nsURL") }
    }
    @Published var secret = Keychain.get("nsSecret") ?? "" {
        didSet { Keychain.set(secret, for: "nsSecret") }
    }
    @Published var uploadDeviceStatus = UserDefaults.standard.object(forKey: "nsDeviceStatus") as? Bool ?? true {
        didSet { UserDefaults.standard.set(uploadDeviceStatus, forKey: "nsDeviceStatus") }
    }
    @Published private(set) var status = "aus"
    @Published private(set) var lastSuccess: Date?
    @Published private(set) var lastError: String?

    private let store: DataStore
    private let log: EventLog
    private var lastEntryUploaded: Date {
        get { Date(timeIntervalSince1970: UserDefaults.standard.double(forKey: "nsLastEntry")) }
        set { UserDefaults.standard.set(newValue.timeIntervalSince1970, forKey: "nsLastEntry") }
    }
    private var lastDeviceStatus: Date = .distantPast
    private var running = false

    init(store: DataStore, log: EventLog) {
        self.store = store
        self.log = log
    }

    /// Uploads only when a new sensor value arrived, then immediately (saves battery).
    /// The pump status of the same refresh cycle goes along with it.
    func newReading() {
        guard enabled else { return }
        Task { [weak self] in await self?.sync() }
    }

    func sync() async {
        guard enabled, !running, let base = baseURL else { return }
        running = true
        defer { running = false }
        let bgTask = UIApplication.shared.beginBackgroundTask(withName: "nightscout-upload")
        defer { UIApplication.shared.endBackgroundTask(bgTask) }
        do {
            let newReadings = store.readings.filter { $0.date > lastEntryUploaded }.suffix(288)
            if !newReadings.isEmpty {
                let body = newReadings.map { Nightscout.entry($0, includeId: false) }
                try await post(base, path: "api/v1/entries", json: body)
                lastEntryUploaded = newReadings.last!.date
                log.add("Nightscout: \(newReadings.count) Wert(e) hochgeladen")
            }
            let snap = store.snapshot
            if uploadDeviceStatus, snap.updatedAt > lastDeviceStatus {
                let level = UIDevice.current.batteryLevel
                let ds = Nightscout.deviceStatus(snap, uploaderBattery: level >= 0 ? Int((level * 100).rounded()) : nil)
                try await post(base, path: "api/v1/devicestatus", json: ds)
                lastDeviceStatus = snap.updatedAt
            }
            lastSuccess = Date()
            lastError = nil
            status = "ok"
        } catch {
            lastError = error.localizedDescription
            status = "Fehler"
            log.add("Nightscout-Upload fehlgeschlagen: \(error.localizedDescription)", .warning)
        }
    }

    /// Checks URL and secret with GET /api/v1/verifyauth (read-only request).
    func test() async -> String {
        guard let base = baseURL else { return "Ungültige URL" }
        do {
            var request = URLRequest(url: base.appendingPathComponent("api/v1/verifyauth"))
            authorize(&request)
            let (data, response) = try await URLSession.shared.data(for: request)
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            guard code == 200 else { return "HTTP \(code)" }
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            if let message = json?["message"] as? [String: Any] {
                if message["canWrite"] as? Bool == true { return "Verbunden, Schreibrecht ok" }
                return "Verbunden, aber kein Schreibrecht – API-Secret prüfen"
            }
            if json?["message"] as? String == "OK" { return "Verbunden, API-Secret ok" }
            return "Verbunden, API-Secret nicht bestätigt"
        } catch {
            return error.localizedDescription
        }
    }

    func resetUploadMarker() {
        lastEntryUploaded = Date().addingTimeInterval(-24 * 3600)
        lastDeviceStatus = .distantPast
    }

    private var baseURL: URL? {
        var s = url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty else { return nil }
        if !s.hasPrefix("http") { s = "https://" + s }
        if !s.hasSuffix("/") { s += "/" }
        guard let u = URL(string: s), u.scheme == "https" || u.host == "localhost" || u.host == "127.0.0.1" else { return nil }
        return u
    }

    private func authorize(_ request: inout URLRequest) {
        guard !secret.isEmpty else { return }
        if secret.hasPrefix("token=") {
            // Access token instead of API secret.
            var c = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)!
            c.queryItems = (c.queryItems ?? []) + [URLQueryItem(name: "token", value: String(secret.dropFirst(6)))]
            request.url = c.url
        } else {
            let sha1 = Insecure.SHA1.hash(data: Data(secret.utf8)).map { String(format: "%02x", $0) }.joined()
            request.setValue(sha1, forHTTPHeaderField: "api-secret")
        }
    }

    private func post(_ base: URL, path: String, json: Any) async throws {
        var request = URLRequest(url: base.appendingPathComponent(path))
        request.httpMethod = "POST"
        request.timeoutInterval = 20
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: json)
        authorize(&request)
        let (_, response) = try await URLSession.shared.data(for: request)
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(code) else {
            throw NSError(domain: "Nightscout", code: code,
                          userInfo: [NSLocalizedDescriptionKey: code == 401 ? "API-Secret falsch (401)" : "HTTP \(code)"])
        }
    }
}
