// SPDX-License-Identifier: GPL-3.0-or-later
// Minimal HTTP server with Nightscout-compatible read endpoints.
//
// Port 17580 like the xDrip+ local web server, so existing clients work unchanged.
// By default only reachable from this iPhone (loopback). LAN access is opt-in and then
// requires the API secret (header `api-secret`: SHA-1 hex or plain, `?token=`, or Basic Auth
// with the secret as password). `/status.html` is a human-readable page (Basic Auth).
//
// Note: iOS suspends the app in the background between Bluetooth events. While
// suspended the server does not answer. See docs/api.md.
import CryptoKit
import Foundation
import MiniMedKit
import Network

final class LocalAPIServer: @unchecked Sendable {
    static let port: UInt16 = 17580

    private let shared: SharedData
    private let queue = DispatchQueue(label: "openminipump.api")
    private var listener: NWListener?
    private var allowLAN = false
    private var secret = ""
    private let version: String
    /// Identifies the current listener. State updates of replaced listeners are ignored;
    /// otherwise a late "cancelled" of the old one overwrote "ready" of the new one.
    private var generation = 0
    private var isReady = false
    private var retryDelay: TimeInterval = 1

    var onStateChange: ((String) -> Void)?
    var onLog: ((String) -> Void)?

    init(shared: SharedData) {
        self.shared = shared
        version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
    }

    func start(allowLAN: Bool, secret: String) {
        queue.async { [self] in
            let lanChanged = allowLAN != self.allowLAN
            self.allowLAN = allowLAN
            // A new secret only affects authorization; no restart needed for that.
            self.secret = secret
            if isReady, !lanChanged { return }
            restart()
        }
    }

    /// iOS takes listening sockets away from suspended apps; call when the app becomes active.
    func ensureRunning() {
        queue.async { [self] in
            if !isReady { restart() }
        }
    }

    func stop() {
        queue.async { [self] in
            generation += 1
            listener?.stateUpdateHandler = nil
            listener?.cancel()
            listener = nil
            isReady = false
            onStateChange?("gestoppt")
        }
    }

    private func restart() {
        generation += 1
        let gen = generation
        if let old = listener {
            old.stateUpdateHandler = nil
            old.newConnectionHandler = nil
            old.cancel()
        }
        listener = nil
        isReady = false
        let lan = allowLAN
        do {
            let params = NWParameters.tcp
            params.allowLocalEndpointReuse = true
            let port = NWEndpoint.Port(rawValue: Self.port)!
            let l: NWListener
            if lan {
                l = try NWListener(using: params, on: port)
            } else {
                params.requiredLocalEndpoint = .hostPort(host: .ipv4(.loopback), port: port)
                l = try NWListener(using: params)
            }
            l.newConnectionHandler = { [weak self] c in self?.accept(c) }
            l.stateUpdateHandler = { [weak self, weak l] state in
                guard let self, gen == self.generation else { return }
                switch state {
                case .ready:
                    self.isReady = true
                    self.retryDelay = 1
                    self.onStateChange?(lan ? "läuft (WLAN, Port \(Self.port))" : "läuft (nur dieses iPhone, Port \(Self.port))")
                case .waiting(let e):
                    self.onStateChange?("wartet: \(e)")
                case .failed(let e):
                    self.isReady = false
                    l?.cancel()
                    let delay = self.retryDelay
                    self.retryDelay = min(self.retryDelay * 2, 30)
                    self.onLog?("API-Server Fehler: \(e), Neustart in \(Int(delay)) s")
                    self.onStateChange?("Neustart nach Fehler …")
                    self.queue.asyncAfter(deadline: .now() + delay) { [weak self] in
                        guard let self, gen == self.generation else { return }
                        self.restart()
                    }
                default:
                    break
                }
            }
            listener = l
            l.start(queue: queue)
        } catch {
            onLog?("API-Server konnte nicht starten: \(error)")
            onStateChange?("Fehler: \(error)")
            let delay = retryDelay
            retryDelay = min(retryDelay * 2, 30)
            queue.asyncAfter(deadline: .now() + delay) { [weak self] in
                guard let self, gen == self.generation else { return }
                self.restart()
            }
        }
    }

    private func accept(_ connection: NWConnection) {
        connection.start(queue: queue)
        receive(connection, buffer: Data())
    }

    private func receive(_ connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 16_384) { [weak self] data, _, done, error in
            guard let self else { return }
            var buffer = buffer
            if let data { buffer.append(data) }
            if let end = buffer.range(of: Data("\r\n\r\n".utf8)) {
                let head = String(decoding: buffer[..<end.lowerBound], as: UTF8.self)
                self.respond(connection, head: head)
            } else if done || error != nil || buffer.count > 16_384 {
                connection.cancel()
            } else {
                self.receive(connection, buffer: buffer)
            }
        }
    }

    private func respond(_ connection: NWConnection, head: String) {
        let lines = head.components(separatedBy: "\r\n")
        let parts = (lines.first ?? "").split(separator: " ")
        guard parts.count >= 2 else { return send(connection, status: "400 Bad Request", json: ["error": "bad request"]) }
        let method = String(parts[0])
        var headers: [String: String] = [:]
        for line in lines.dropFirst() {
            if let i = line.firstIndex(of: ":") {
                headers[line[..<i].lowercased()] = line[line.index(after: i)...].trimmingCharacters(in: .whitespaces)
            }
        }
        let components = URLComponents(string: String(parts[1])) ?? URLComponents()
        var query: [String: String] = [:]
        for item in components.queryItems ?? [] { query[item.name] = item.value ?? "" }

        if method == "OPTIONS" { return send(connection, status: "204 No Content", body: Data(), type: "text/plain") }
        guard method == "GET" || method == "HEAD" else {
            return send(connection, status: "405 Method Not Allowed", json: ["error": "read-only API"])
        }
        let path = components.path.lowercased()
        let wantsHTML = path == "/status.html" || (path == "/" && (headers["accept"] ?? "").contains("text/html"))
        if wantsHTML {
            // Human-readable page: Basic Auth with the API secret as password (any user name).
            guard htmlAuthorized(connection, headers: headers) else {
                return send(connection, status: "401 Unauthorized",
                            body: Data("Anmeldung erforderlich: Benutzername beliebig, Passwort = API-Secret.".utf8),
                            type: "text/plain; charset=utf-8",
                            extraHeaders: ["WWW-Authenticate": "Basic realm=\"openMinipump\", charset=\"UTF-8\""])
            }
            let (readings, snapshot, battery) = shared.get()
            return send(connection, status: "200 OK",
                        body: Data(StatusPage.html(readings: readings, snapshot: snapshot, uploaderBattery: battery, version: version).utf8),
                        type: "text/html; charset=utf-8")
        }
        guard authorized(connection, headers: headers, query: query) else {
            return send(connection, status: "401 Unauthorized", json: ["status": 401, "message": "api-secret fehlt oder falsch"])
        }

        let (readings, snapshot, uploaderBattery) = shared.get()
        let newestFirst = readings.sorted { $0.date > $1.date }

        switch path {
        case "/api/v1/entries.json", "/api/v1/entries", "/api/v1/entries/sgv.json", "/api/v1/entries/sgv", "/sgv.json":
            let count = Int(query["count"] ?? "") ?? 10
            send(connection, json: filtered(newestFirst, query).prefix(max(0, count)).map { Nightscout.entry($0) })
        case "/api/v1/entries/current.json", "/api/v1/entries/current":
            send(connection, json: newestFirst.prefix(1).map { Nightscout.entry($0) })
        case "/api/v1/devicestatus.json", "/api/v1/devicestatus":
            let hasData = snapshot.updatedAt > .distantPast
            send(connection, json: hasData ? [Nightscout.deviceStatus(snapshot, uploaderBattery: uploaderBattery)] : [])
        case "/api/v1/treatments.json", "/api/v1/treatments":
            send(connection, json: [[String: Any]]())
        case "/api/v1/status.json", "/api/v1/status":
            send(connection, json: Nightscout.status(version: version))
        case "/pebble":
            let count = Int(query["count"] ?? "") ?? 1
            let mmol = (query["units"] ?? "").lowercased().hasPrefix("mmol")
            send(connection, json: Nightscout.pebble(readings: readings, snapshot: snapshot, uploaderBattery: uploaderBattery,
                                                     count: count, mmol: mmol))
        case "/", "/api/v1":
            send(connection, json: ["name": "openMinipump", "readOnly": true, "endpoints": [
                "/status.html", "/api/v1/entries.json?count=N", "/api/v1/entries/current.json", "/api/v1/devicestatus.json",
                "/api/v1/treatments.json", "/api/v1/status.json", "/pebble", "/sgv.json",
            ]] as [String: Any])
        default:
            send(connection, status: "404 Not Found", json: ["status": 404, "message": "not found"])
        }
    }

    /// Supports find[date][$gte|$gt|$lte|$lt]=<ms>, as used by Nightscout clients.
    private func filtered(_ readings: [GlucoseReading], _ query: [String: String]) -> [GlucoseReading] {
        readings.filter { r in
            let ms = Double(Nightscout.millis(r.date))
            if let v = query["find[date][$gte]"].flatMap(Double.init), ms < v { return false }
            if let v = query["find[date][$gt]"].flatMap(Double.init), ms <= v { return false }
            if let v = query["find[date][$lte]"].flatMap(Double.init), ms > v { return false }
            if let v = query["find[date][$lt]"].flatMap(Double.init), ms >= v { return false }
            return true
        }
    }

    private func isLoopback(_ connection: NWConnection) -> Bool {
        guard case .hostPort(let host, _) = connection.endpoint else { return false }
        let h = "\(host)"
        return h == "127.0.0.1" || h == "::1" || h.hasPrefix("::ffff:127.")
    }

    private func basicAuthPassword(_ headers: [String: String]) -> String? {
        guard let value = headers["authorization"], value.lowercased().hasPrefix("basic "),
              let data = Data(base64Encoded: String(value.dropFirst(6)).trimmingCharacters(in: .whitespaces)),
              let decoded = String(data: data, encoding: .utf8), let colon = decoded.firstIndex(of: ":") else { return nil }
        return String(decoded[decoded.index(after: colon)...])
    }

    private func htmlAuthorized(_ connection: NWConnection, headers: [String: String]) -> Bool {
        if secret.isEmpty { return isLoopback(connection) }
        return basicAuthPassword(headers) == secret
    }

    private func authorized(_ connection: NWConnection, headers: [String: String], query: [String: String]) -> Bool {
        if isLoopback(connection) { return true }
        guard allowLAN, !secret.isEmpty else { return false }
        if basicAuthPassword(headers) == secret { return true }
        let sha1 = Insecure.SHA1.hash(data: Data(secret.utf8)).map { String(format: "%02x", $0) }.joined()
        let given = headers["api-secret"] ?? query["token"] ?? ""
        return given == secret || given.lowercased() == sha1
    }

    private func send(_ connection: NWConnection, status: String = "200 OK", json: Any) {
        let body = (try? JSONSerialization.data(withJSONObject: json, options: [.sortedKeys])) ?? Data("{}".utf8)
        send(connection, status: status, body: body, type: "application/json; charset=utf-8")
    }

    private func send(_ connection: NWConnection, status: String, body: Data, type: String,
                      extraHeaders: [String: String] = [:]) {
        var head = "HTTP/1.1 \(status)\r\n"
        for (k, v) in extraHeaders { head += "\(k): \(v)\r\n" }
        head += "Content-Type: \(type)\r\n"
        head += "Content-Length: \(body.count)\r\n"
        head += "Access-Control-Allow-Origin: *\r\n"
        head += "Access-Control-Allow-Headers: api-secret, authorization, content-type\r\n"
        head += "Cache-Control: no-store\r\n"
        head += "Connection: close\r\n\r\n"
        connection.send(content: Data(head.utf8) + body, completion: .contentProcessed { _ in connection.cancel() })
    }
}
