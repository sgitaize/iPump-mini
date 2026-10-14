// SPDX-License-Identifier: GPL-3.0-or-later
// Minimal HTTP server with Nightscout-compatible read endpoints.
//
// Port 17580 like the xDrip+ local web server, so existing clients work unchanged.
// By default only reachable from this iPhone (loopback). LAN access is opt-in and then
// requires the API secret (header `api-secret`: SHA-1 hex or plain, or `?token=`).
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

    var onStateChange: ((String) -> Void)?

    init(shared: SharedData) {
        self.shared = shared
        version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
    }

    func start(allowLAN: Bool, secret: String) {
        queue.async { [self] in
            listener?.cancel()
            self.allowLAN = allowLAN
            self.secret = secret
            do {
                let params = NWParameters.tcp
                params.allowLocalEndpointReuse = true
                let port = NWEndpoint.Port(rawValue: Self.port)!
                let l: NWListener
                if allowLAN {
                    l = try NWListener(using: params, on: port)
                } else {
                    params.requiredLocalEndpoint = .hostPort(host: .ipv4(.loopback), port: port)
                    l = try NWListener(using: params)
                }
                l.newConnectionHandler = { [weak self] c in self?.accept(c) }
                l.stateUpdateHandler = { [weak self] state in
                    let text: String
                    switch state {
                    case .ready: text = allowLAN ? "läuft (WLAN, Port \(Self.port))" : "läuft (nur dieses iPhone, Port \(Self.port))"
                    case .failed(let e): text = "Fehler: \(e)"
                    case .cancelled: text = "gestoppt"
                    default: return
                    }
                    self?.onStateChange?(text)
                }
                l.start(queue: queue)
                listener = l
            } catch {
                onStateChange?("Fehler: \(error)")
            }
        }
    }

    func stop() { queue.async { [self] in listener?.cancel(); listener = nil } }

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
        guard authorized(connection, headers: headers, query: query) else {
            return send(connection, status: "401 Unauthorized", json: ["status": 401, "message": "api-secret fehlt oder falsch"])
        }

        let (readings, snapshot, uploaderBattery) = shared.get()
        let path = components.path.lowercased()
        let newestFirst = readings.sorted { $0.date > $1.date }

        switch path {
        case "/api/v1/entries.json", "/api/v1/entries", "/api/v1/entries/sgv.json", "/api/v1/entries/sgv", "/sgv.json":
            let count = Int(query["count"] ?? "") ?? 10
            send(connection, json: filtered(newestFirst, query).prefix(max(0, count)).map(Nightscout.entry))
        case "/api/v1/entries/current.json", "/api/v1/entries/current":
            send(connection, json: newestFirst.prefix(1).map(Nightscout.entry))
        case "/api/v1/devicestatus.json", "/api/v1/devicestatus":
            let hasData = snapshot.updatedAt > .distantPast
            send(connection, json: hasData ? [Nightscout.deviceStatus(snapshot, uploaderBattery: uploaderBattery)] : [])
        case "/api/v1/treatments.json", "/api/v1/treatments":
            send(connection, json: [[String: Any]]())
        case "/api/v1/status.json", "/api/v1/status":
            send(connection, json: Nightscout.status(version: version))
        case "/pebble":
            send(connection, json: Nightscout.pebble(readings: readings, snapshot: snapshot, uploaderBattery: uploaderBattery))
        case "/", "/api/v1":
            send(connection, json: ["name": "openMinipump", "readOnly": true, "endpoints": [
                "/api/v1/entries.json?count=N", "/api/v1/entries/current.json", "/api/v1/devicestatus.json",
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

    private func authorized(_ connection: NWConnection, headers: [String: String], query: [String: String]) -> Bool {
        if case .hostPort(let host, _) = connection.endpoint {
            let h = "\(host)"
            if h == "127.0.0.1" || h == "::1" || h.hasPrefix("::ffff:127.") { return true }
        }
        guard allowLAN, !secret.isEmpty else { return false }
        let sha1 = Insecure.SHA1.hash(data: Data(secret.utf8)).map { String(format: "%02x", $0) }.joined()
        let given = headers["api-secret"] ?? query["token"] ?? ""
        return given == secret || given.lowercased() == sha1
    }

    private func send(_ connection: NWConnection, status: String = "200 OK", json: Any) {
        let body = (try? JSONSerialization.data(withJSONObject: json, options: [.sortedKeys])) ?? Data("{}".utf8)
        send(connection, status: status, body: body, type: "application/json; charset=utf-8")
    }

    private func send(_ connection: NWConnection, status: String, body: Data, type: String) {
        var head = "HTTP/1.1 \(status)\r\n"
        head += "Content-Type: \(type)\r\n"
        head += "Content-Length: \(body.count)\r\n"
        head += "Access-Control-Allow-Origin: *\r\n"
        head += "Access-Control-Allow-Headers: api-secret, content-type\r\n"
        head += "Cache-Control: no-store\r\n"
        head += "Connection: close\r\n\r\n"
        connection.send(content: Data(head.utf8) + body, completion: .contentProcessed { _ in connection.cancel() })
    }
}
