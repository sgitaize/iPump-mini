// SPDX-License-Identifier: GPL-3.0-or-later
// End to end: the real server on loopback (port 17580), asked with URLSession.
// Loopback needs no secret, so the LAN authorisation is not covered here.
import XCTest
import MiniMedKit
@testable import OpenMinipump

final class LocalAPIServerTests: XCTestCase {
    private static let shared = SharedData()
    private static var server: LocalAPIServer?
    private static let port: UInt16 = 17591
    private static let base = "http://127.0.0.1:\(port)"
    private let session = URLSession(configuration: .ephemeral)

    private let now = Date()

    override func setUp() async throws {
        if Self.server == nil {
            let s = LocalAPIServer(shared: Self.shared, port: Self.port)
            s.start(allowLAN: false, secret: "")
            Self.server = s
            for _ in 0..<50 {
                if (try? await get("/api/v1/status.json"))?.status == 200 { break }
                try await Task.sleep(nanoseconds: 100_000_000)
            }
        }
        Self.shared.set(readings: [], snapshot: PumpSnapshot(), treatments: [], uploaderBattery: nil)
    }

    override class func tearDown() {
        server?.stop()
        server = nil
    }

    // MARK: helpers

    struct Response { let status: Int; let data: Data; let http: HTTPURLResponse
        var json: Any { try! JSONSerialization.jsonObject(with: data) }
        var array: [[String: Any]] { json as! [[String: Any]] }
        var object: [String: Any] { json as! [String: Any] }
    }

    private func get(_ path: String, method: String = "GET", headers: [String: String] = [:]) async throws -> Response {
        var req = URLRequest(url: URL(string: Self.base + path)!)
        req.httpMethod = method
        req.timeoutInterval = 3
        for (k, v) in headers { req.setValue(v, forHTTPHeaderField: k) }
        let (data, resp) = try await session.data(for: req)
        let http = resp as! HTTPURLResponse
        return Response(status: http.statusCode, data: data, http: http)
    }

    /// Readings every 5 minutes, newest `minutesAgo` 0, deliberately stored unsorted.
    private func load(_ values: [Int], snapshot: PumpSnapshot = PumpSnapshot(), treatments: [Treatment] = []) {
        let readings = values.enumerated().map {
            GlucoseReading(date: now.addingTimeInterval(-Double($0.offset) * 300), mgdl: $0.element, trendMgdlPerMin: 0.3, sessionOffsetMinutes: UInt16($0.offset))
        }
        Self.shared.set(readings: readings.shuffled(), snapshot: snapshot, treatments: treatments, uploaderBattery: 77)
    }

    private func ms(_ minutesAgo: Double) -> Int64 { Nightscout.millis(now.addingTimeInterval(-minutesAgo * 60)) }

    // MARK: entries

    func testEntriesNewestFirstWithDefaultCountTen() async throws {
        load(Array(100..<130))
        let r = try await get("/api/v1/entries.json")
        XCTAssertEqual(r.status, 200)
        XCTAssertEqual(r.array.count, 10)
        let dates = r.array.map { ($0["date"] as! NSNumber).int64Value }
        XCTAssertEqual(dates, dates.sorted(by: >))
        XCTAssertEqual(r.array[0]["sgv"] as? Int, 100)
    }

    func testAllEntryAliasesAnswer() async throws {
        load([120, 121])
        for path in ["/api/v1/entries.json", "/api/v1/entries", "/api/v1/entries/sgv.json", "/api/v1/entries/sgv", "/sgv.json", "/API/V1/Entries.json"] {
            let r = try await get(path + "?count=1")
            XCTAssertEqual(r.status, 200, path)
            XCTAssertEqual(r.array.count, 1, path)
        }
    }

    func testCountParsing() async throws {
        load(Array(100..<120))
        let cases: [(String, Int)] = [("count=3", 3), ("count=0", 0), ("count=-4", 0), ("count=abc", 10), ("count=", 10), ("count=1000", 20)]
        for (q, n) in cases {
            let r = try await get("/api/v1/entries.json?\(q)")
            XCTAssertEqual(r.array.count, n, q)
        }
    }

    func testFindDateFilters() async throws {
        load(Array(100..<110))   // minutes ago: 0, 5, ... 45
        let cutoff = ms(20)       // exactly the value 20 min ago
        func ids(_ query: String) async throws -> [Int] {
            try await get("/api/v1/entries.json?count=100&" + query).array.map { $0["sgv"] as! Int }
        }
        let gte = try await ids("find%5Bdate%5D%5B%24gte%5D=\(cutoff)")
        XCTAssertEqual(gte, [100, 101, 102, 103, 104])
        let gt = try await ids("find%5Bdate%5D%5B%24gt%5D=\(cutoff)")
        XCTAssertEqual(gt, [100, 101, 102, 103])
        let lte = try await ids("find%5Bdate%5D%5B%24lte%5D=\(cutoff)")
        XCTAssertEqual(lte, [104, 105, 106, 107, 108, 109])
        let lt = try await ids("find%5Bdate%5D%5B%24lt%5D=\(cutoff)")
        XCTAssertEqual(lt, [105, 106, 107, 108, 109])
        let window = try await ids("find%5Bdate%5D%5B%24gte%5D=\(ms(26))&find%5Bdate%5D%5B%24lt%5D=\(ms(9))")
        XCTAssertEqual(window, [102, 103, 104, 105])
    }

    func testFindDateWithLiteralBracketsAndGarbage() async throws {
        load(Array(100..<110))
        let literal = "/api/v1/entries.json?count=100&find[date][$gte]=\(ms(7))"
        if URL(string: Self.base + literal) != nil {
            let r = try await get(literal)
            XCTAssertEqual(r.array.count, 2)
        }
        let garbage = try await get("/api/v1/entries.json?count=100&find%5Bdate%5D%5B%24gte%5D=notanumber")
        XCTAssertEqual(garbage.array.count, 10, "an unparsable bound is ignored, not an error")
    }

    func testEntryFieldsAndTypes() async throws {
        load([142])
        let e = try await get("/api/v1/entries/current.json").array[0]
        XCTAssertEqual(e["type"] as? String, "sgv")
        XCTAssertTrue(e["sgv"] is Int || e["sgv"] is NSNumber)
        XCTAssertEqual(e["sgv"] as? Int, 142)
        XCTAssertTrue(e["date"] is NSNumber)
        XCTAssertTrue(e["dateString"] is String)
        XCTAssertTrue(e["direction"] is String)
        XCTAssertTrue(e["trend"] is NSNumber)
        XCTAssertTrue((e["_id"] as? String)?.hasPrefix("omp-") == true)
        XCTAssertEqual(e["device"] as? String, "openMinipump")
    }

    func testCurrentWithoutDataIsEmptyArray() async throws {
        let r = try await get("/api/v1/entries/current.json")
        XCTAssertEqual(r.status, 200)
        XCTAssertTrue(r.array.isEmpty)
    }

    // MARK: other endpoints

    func testDeviceStatusEmptyUntilFirstSnapshot() async throws {
        let r1 = try await get("/api/v1/devicestatus.json")
        XCTAssertTrue(r1.array.isEmpty)
        var s = PumpSnapshot(updatedAt: now); s.pumpBatteryPercent = 80
        load([120], snapshot: s)
        let ds = try await get("/api/v1/devicestatus").array
        XCTAssertEqual(ds.count, 1)
        XCTAssertEqual(ds[0]["uploaderBattery"] as? Int, 77)
        XCTAssertNotNil((ds[0]["pump"] as? [String: Any])?["battery"])
    }

    func testTreatmentsIncludeAutoBasalSortedAndCounted() async throws {
        let t = [
            Treatment(id: 1, date: now.addingTimeInterval(-3000), kind: .bolus, value: 2),
            Treatment(id: 2, date: now.addingTimeInterval(-1000), kind: .autoBasal, value: 0.05),
            Treatment(id: 3, date: now.addingTimeInterval(-2000), kind: .carbs, value: 30),
            Treatment(id: 4, date: now.addingTimeInterval(-500), kind: .basalChange, value: 0.8),
        ]
        load([120], treatments: t)
        let all = try await get("/api/v1/treatments.json").array
        XCTAssertEqual(all.map { $0["pumpId"] as? Int }, [2, 3, 1], "newest first, basal changes are not exported")
        let r2 = try await get("/api/v1/treatments.json?count=1")
        XCTAssertEqual(r2.array.count, 1)
        let r3 = try await get("/api/v1/treatments.json?count=0")
        XCTAssertEqual(r3.array.count, 0)
    }

    func testStatusJson() async throws {
        let o = try await get("/api/v1/status.json").object
        XCTAssertEqual(o["status"] as? String, "ok")
        XCTAssertEqual(o["apiEnabled"] as? Bool, true)
        XCTAssertEqual((o["settings"] as? [String: Any])?["units"] as? String, "mg/dl")
        let epoch = (o["serverTimeEpoch"] as! NSNumber).int64Value
        XCTAssertEqual(Double(epoch) / 1000, Date().timeIntervalSince1970, accuracy: 10)
    }

    func testPebble() async throws {
        load([126, 120, 118])
        let o = try await get("/pebble?count=2").object
        let bgs = o["bgs"] as! [[String: Any]]
        XCTAssertEqual(bgs.count, 2)
        XCTAssertEqual(bgs[0]["sgv"] as? String, "126")
        XCTAssertEqual(bgs[0]["bgdelta"] as? Double, 6)
        let mmol = try await get("/pebble?units=mmol").object["bgs"] as! [[String: Any]]
        XCTAssertEqual(mmol[0]["sgv"] as? String, "7.0")
        XCTAssertNil(o["ompSync"], "no wake recorded yet")
        Self.shared.recordWake(Date().addingTimeInterval(-60))
        let sync = try await get("/pebble").object["ompSync"] as? [String: Any]
        XCTAssertEqual(sync?["windowSec"] as? Int, LocalAPIServer.awakeWindow)
        XCTAssertTrue((sync?["nextWake"] as? NSNumber)?.int64Value ?? 0 > Nightscout.millis(Date()))
    }

    func testIndexAndHTMLNegotiation() async throws {
        let json = try await get("/")
        XCTAssertEqual(json.object["readOnly"] as? Bool, true)
        XCTAssertTrue(json.http.value(forHTTPHeaderField: "Content-Type")!.hasPrefix("application/json"))
        load([120], snapshot: PumpSnapshot(updatedAt: now))
        let html = try await get("/", headers: ["Accept": "text/html"])
        XCTAssertEqual(html.status, 200)
        XCTAssertTrue(html.http.value(forHTTPHeaderField: "Content-Type")!.hasPrefix("text/html"))
        XCTAssertTrue(String(decoding: html.data, as: UTF8.self).contains("<html"))
        let r4 = try await get("/status.html")
        XCTAssertEqual(r4.status, 200)
    }

    // MARK: protocol behaviour

    func testOnlyReadMethods() async throws {
        for m in ["POST", "PUT", "DELETE", "PATCH"] {
            let r = try await get("/api/v1/entries.json", method: m)
            XCTAssertEqual(r.status, 405, m)
            XCTAssertEqual(r.object["error"] as? String, "read-only API")
        }
        let r5 = try await get("/api/v1/entries.json", method: "OPTIONS")
        XCTAssertEqual(r5.status, 204)
        let r6 = try await get("/api/v1/entries.json", method: "HEAD")
        XCTAssertEqual(r6.status, 200)
    }

    func testUnknownPathIs404Json() async throws {
        let r = try await get("/api/v1/profile.json")
        XCTAssertEqual(r.status, 404)
        XCTAssertEqual(r.object["status"] as? Int, 404)
    }

    func testCORSAndNoStoreHeaders() async throws {
        let r = try await get("/api/v1/status.json")
        XCTAssertEqual(r.http.value(forHTTPHeaderField: "Access-Control-Allow-Origin"), "*")
        XCTAssertEqual(r.http.value(forHTTPHeaderField: "Cache-Control"), "no-store")
        XCTAssertEqual(r.http.value(forHTTPHeaderField: "Content-Length"), String(r.data.count))
    }

    // MARK: plausibility of what clients see

    func testDemoStyleDataIsConsistentAcrossEndpoints() async throws {
        let values = (0..<72).map { Int(130 + 50 * sin(Double($0) / 9)) }
        load(values)
        let entries = try await get("/api/v1/entries.json?count=288").array
        XCTAssertEqual(entries.count, 72)
        XCTAssertTrue(entries.allSatisfy { (40...400).contains($0["sgv"] as! Int) })
        let ms = entries.map { ($0["date"] as! NSNumber).int64Value }
        XCTAssertTrue(zip(ms, ms.dropFirst()).allSatisfy { $0 - $1 == 300_000 }, "no gaps or duplicates")
        XCTAssertTrue(ms.allSatisfy { $0 <= Nightscout.millis(Date()) + 1000 }, "nothing from the future")
        let allowed: Set<Int> = [0, 1, 2, 4, 6, 7]
        XCTAssertTrue(entries.allSatisfy { allowed.contains(($0["trend"] as! NSNumber).intValue) })
        let pebble = try await get("/pebble").object["bgs"] as! [[String: Any]]
        XCTAssertEqual(pebble[0]["sgv"] as? String, String(entries[0]["sgv"] as! Int))
    }
}
