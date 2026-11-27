// SPDX-License-Identifier: GPL-3.0-or-later
// Plausibility checks for the data mapping (Nightscout shapes, treatments, history timeline).
import XCTest
@testable import MiniMedKit

final class DirectionPlausibilityTests: XCTestCase {
    func testArrowBoundariesAreSymmetric() {
        let cases: [(Double, String, Int)] = [
            (0, "Flat", 4), (0.99, "Flat", 4), (-0.99, "Flat", 4),
            (1, "SingleUp", 2), (-1, "SingleDown", 6),
            (1.99, "SingleUp", 2), (-1.99, "SingleDown", 6),
            (2, "DoubleUp", 1), (-2, "DoubleDown", 7),
            (3.5, "DoubleUp", 1), (-3.5, "DoubleDown", 7),
        ]
        for (rate, name, trend) in cases {
            let d = Nightscout.direction(forRate: rate)
            XCTAssertEqual(d.name, name, "rate \(rate)")
            XCTAssertEqual(d.trend, trend, "rate \(rate)")
        }
        XCTAssertEqual(Nightscout.direction(forRate: nil).trend, 0)
    }

    func testDirectionIsMonotonic() {
        // Falling rate never gets a "higher" trend number than rising (1 = DoubleUp ... 7 = DoubleDown, 4 = Flat).
        var last = 0
        for rate in stride(from: 4.0, through: -4.0, by: -0.05) {
            let t = Nightscout.direction(forRate: rate).trend
            XCTAssertGreaterThanOrEqual(t, last, "rate \(rate)")
            last = t
        }
    }
}

final class NightscoutShapePlausibilityTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_760_000_000)

    func testEntryFieldNamesAndTypes() throws {
        let r = GlucoseReading(date: t0, mgdl: 142, trendMgdlPerMin: 0.5, sessionOffsetMinutes: 10)
        let e = Nightscout.entry(r)
        XCTAssertEqual(e["type"] as? String, "sgv")
        XCTAssertEqual(e["sgv"] as? Int, 142)
        XCTAssertEqual(e["date"] as? Int64, 1_760_000_000_000)
        XCTAssertEqual(e["trend"] as? Int, 4)
        XCTAssertEqual(e["direction"] as? String, "Flat")
        XCTAssertEqual(e["device"] as? String, "openMinipump")
        XCTAssertEqual(e["_id"] as? String, "omp-1760000000000")
        XCTAssertNotNil(e["utcOffset"] as? Int)
        XCTAssertEqual(e["trendRate"] as? Double, 0.5)
        // dateString is ISO 8601 with milliseconds and parses back to the same instant.
        let s = try XCTUnwrap(e["dateString"] as? String)
        XCTAssertTrue(s.hasSuffix("Z"))
        let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        XCTAssertEqual(f.date(from: s), t0)
        XCTAssertNil(Nightscout.entry(r, includeId: false)["_id"])
        XCTAssertNil(Nightscout.entry(GlucoseReading(date: t0, mgdl: 100, trendMgdlPerMin: nil, sessionOffsetMinutes: nil))["trendRate"])
        XCTAssertEqual(Nightscout.entry(GlucoseReading(date: t0, mgdl: 100, trendMgdlPerMin: nil, sessionOffsetMinutes: nil))["direction"] as? String, "NONE")
    }

    func testEntryIsValidJSONRoundTrip() throws {
        let e = Nightscout.entry(GlucoseReading(date: t0, mgdl: 90, trendMgdlPerMin: -1.2, sessionOffsetMinutes: 1))
        let data = try JSONSerialization.data(withJSONObject: [e])
        let back = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [[String: Any]])
        XCTAssertEqual(back[0]["sgv"] as? Int, 90)
        XCTAssertEqual((back[0]["date"] as? NSNumber)?.int64Value, 1_760_000_000_000)
    }

    func testDeviceStatusShape() throws {
        var s = PumpSnapshot(updatedAt: t0)
        s.pumpBatteryPercent = 70
        s.sensorEnd = t0.addingTimeInterval(86400)
        let ds = Nightscout.deviceStatus(s, uploaderBattery: 55)
        XCTAssertEqual(ds["device"] as? String, "openMinipump")
        XCTAssertNotNil(ds["created_at"] as? String)
        XCTAssertEqual(ds["uploaderBattery"] as? Int, 55)
        let pump = try XCTUnwrap(ds["pump"] as? [String: Any])
        XCTAssertNotNil(pump["clock"] as? String)
        XCTAssertEqual((pump["battery"] as? [String: Any])?["percent"] as? Int, 70)
        XCTAssertNotNil((pump["extended"] as? [String: Any])?["sensorEnd"] as? String)
        XCTAssertTrue(JSONSerialization.isValidJSONObject(ds))
        // Without any pump part there is no reservoir/iob and no uploader battery key.
        let empty = Nightscout.deviceStatus(PumpSnapshot(updatedAt: t0), uploaderBattery: nil)
        XCTAssertNil(empty["uploaderBattery"])
        XCTAssertNil((empty["pump"] as? [String: Any])?["reservoir"])
    }

    func testStatusShape() {
        let s = Nightscout.status(version: "1.2.3", now: t0)
        XCTAssertEqual(s["status"] as? String, "ok")
        XCTAssertEqual(s["version"] as? String, "1.2.3")
        XCTAssertEqual(s["serverTimeEpoch"] as? Int64, 1_760_000_000_000)
        XCTAssertEqual(s["apiEnabled"] as? Bool, true)
        XCTAssertEqual((s["settings"] as? [String: Any])?["units"] as? String, "mg/dl")
    }

    func testPebbleDeltaAndUnits() throws {
        let readings = [
            GlucoseReading(date: t0, mgdl: 126, trendMgdlPerMin: 1.3, sessionOffsetMinutes: 2),
            GlucoseReading(date: t0.addingTimeInterval(-300), mgdl: 120, trendMgdlPerMin: 0.2, sessionOffsetMinutes: 1),
        ]
        let p = Nightscout.pebble(readings: readings.shuffled(), snapshot: nil, uploaderBattery: 80, count: 2, now: t0)
        let bgs = try XCTUnwrap(p["bgs"] as? [[String: Any]])
        XCTAssertEqual(bgs.count, 2)
        XCTAssertEqual(bgs[0]["sgv"] as? String, "126", "sgv is a string and newest first")
        XCTAssertEqual(bgs[0]["bgdelta"] as? Double, 6)
        XCTAssertEqual(bgs[0]["battery"] as? String, "80")
        XCTAssertNil(bgs[1]["bgdelta"])
        XCTAssertEqual(((p["status"] as? [[String: Any]])?.first)?["now"] as? Int64, 1_760_000_000_000)
        // mmol: one decimal, string
        let m = Nightscout.pebble(readings: readings, snapshot: nil, uploaderBattery: nil, mmol: true, now: t0)
        XCTAssertEqual(((m["bgs"] as? [[String: Any]])?.first)?["sgv"] as? String, "7.0")
    }

    func testPebbleGapSuppressesDelta() throws {
        let readings = [
            GlucoseReading(date: t0, mgdl: 200, trendMgdlPerMin: 0, sessionOffsetMinutes: 2),
            GlucoseReading(date: t0.addingTimeInterval(-20 * 60), mgdl: 100, trendMgdlPerMin: 0, sessionOffsetMinutes: 1),
        ]
        let bgs = try XCTUnwrap(Nightscout.pebble(readings: readings, snapshot: nil, uploaderBattery: nil, now: t0)["bgs"] as? [[String: Any]])
        XCTAssertEqual(bgs[0]["bgdelta"] as? Int, 0, "a 20 min gap must not produce a +100 delta")
    }

    func testPebbleCountIsClamped() throws {
        let readings = (0..<150).map { GlucoseReading(date: t0.addingTimeInterval(Double(-$0) * 300), mgdl: 100, trendMgdlPerMin: 0, sessionOffsetMinutes: nil) }
        func n(_ c: Int) -> Int { (Nightscout.pebble(readings: readings, snapshot: nil, uploaderBattery: nil, count: c)["bgs"] as? [Any])?.count ?? -1 }
        XCTAssertEqual(n(0), 1)
        XCTAssertEqual(n(-5), 1)
        XCTAssertEqual(n(1000), 100)
    }
}

final class TreatmentPlausibilityTests: XCTestCase {
    private let d = Date(timeIntervalSince1970: 1_760_000_000)

    func testZeroAndNegativeAmountsAreNotTreatments() {
        func t(_ e: HistoryEvent) -> Treatment? { Treatment(TimedHistoryEvent(sequence: 1, date: d, event: e)) }
        XCTAssertNil(t(.bolusDelivered(id: 1, fastUnits: 0, extendedUnits: 0, durationMinutes: 0)))
        XCTAssertNil(t(.autoBasal(units: 0)))
        XCTAssertNil(t(.meal(grams: 0)))
        XCTAssertNil(t(.sensorGlucose(mgdl: 100)))
        XCTAssertNil(t(.annunciation(id: 1, type: 7, status: 0x33)))
        XCTAssertEqual(t(.bolusDelivered(id: 1, fastUnits: 1.5, extendedUnits: 1, durationMinutes: 30))?.value, 2.5)
    }

    func testDuplicateSequenceNumbersInRecordsStayDistinctByKind() {
        // Re-reading the same history must give identical treatment ids (dedupe key).
        let events = [
            TimedHistoryEvent(sequence: 10, date: d, event: .meal(grams: 20)),
            TimedHistoryEvent(sequence: 11, date: d, event: .bolusDelivered(id: 1, fastUnits: 2, extendedUnits: 0, durationMinutes: 0)),
        ]
        XCTAssertEqual(Treatment.from(events), Treatment.from(events.reversed()))
        XCTAssertEqual(Set(Treatment.from(events).map(\.id)).count, 2)
    }

    func testNightscoutTreatmentShapes() throws {
        for kind in [Treatment.Kind.bolus, .autoCorrection, .carbs, .bgCheck, .calibration, .suspend, .resume] {
            let ns = try XCTUnwrap(Nightscout.treatment(Treatment(id: 9, date: d, kind: kind, value: 12)), "\(kind)")
            XCTAssertNotNil(ns["created_at"] as? String)
            XCTAssertNotNil(ns["eventType"] as? String)
            XCTAssertEqual(ns["enteredBy"] as? String, "openMinipump")
            XCTAssertEqual(ns["pumpId"] as? Int, 9)
            XCTAssertTrue(JSONSerialization.isValidJSONObject(ns))
        }
        XCTAssertNil(Nightscout.treatment(Treatment(id: 1, date: d, kind: .basalChange, value: 0.5), includeAutoBasal: true))
    }

    func testInsulinAmountIsExactDecimal() throws {
        let ns = try XCTUnwrap(Nightscout.treatment(Treatment(id: 1, date: d, kind: .autoBasal, value: 0.05), includeAutoBasal: true))
        let data = try JSONSerialization.data(withJSONObject: ns)
        XCTAssertTrue(String(decoding: data, as: UTF8.self).contains("\"insulin\":0.05"), "no 0.05000000000000003")
    }

    func testBgCheckUnitsAndKinds() throws {
        let cal = try XCTUnwrap(Nightscout.treatment(Treatment(id: 1, date: d, kind: .calibration, value: 152)))
        XCTAssertEqual(cal["eventType"] as? String, "BG Check")
        XCTAssertEqual(cal["units"] as? String, "mg/dl")
        XCTAssertEqual((cal["glucose"] as? NSNumber)?.intValue, 152)
    }
}

final class HistoryTimelinePlausibilityTests: XCTestCase {
    private let utc = TimeZone(identifier: "UTC")!

    private func rec(_ type: UInt16, _ seq: UInt32, _ offset: UInt16, _ payload: [UInt8]) throws -> HistoryRecord {
        try HistoryRecord([UInt8(type & 0xFF), UInt8(type >> 8)]
            + (0..<4).map { UInt8((seq >> (8 * UInt32($0))) & 0xFF) }
            + [UInt8(offset & 0xFF), UInt8(offset >> 8)] + payload)
    }
    private func ref(_ seq: UInt32, hour: UInt8) throws -> HistoryRecord {
        try rec(0xF00E, seq, 0, [0x3c, 0xea, 0x07, 10, 15, hour, 0, 0])
    }
    private func meal(_ seq: UInt32, _ offset: UInt16) throws -> HistoryRecord { try rec(0xF005, seq, offset, [0x2d, 0x00]) }

    func testEventsBeforeReferenceAreDropped() throws {
        let (events, ref0) = HistoryTimeline.resolve([try meal(5, 10)], reference: nil, timeZone: utc)
        XCTAssertTrue(events.isEmpty)
        XCTAssertNil(ref0)
    }

    func testEventOlderThanStoredReferenceIsDropped() throws {
        let r = (sequence: UInt32(100), date: Date(timeIntervalSince1970: 1_760_000_000))
        let (events, _) = HistoryTimeline.resolve([try meal(99, 10), try meal(101, 10)], reference: r, timeZone: utc)
        XCTAssertEqual(events.map(\.sequence), [101])
    }

    func testResultIsChronologicalAndNotInTheFuture() throws {
        let records = try [ref(1, hour: 8), meal(2, 60), meal(3, 120), meal(4, 3000), ref(5, hour: 9), meal(6, 30)]
        let (events, _) = HistoryTimeline.resolve(records.shuffled(), reference: nil, timeZone: utc)
        XCTAssertEqual(events.map(\.sequence), [2, 3, 4, 6])
        XCTAssertEqual(events.map(\.date), events.map(\.date).sorted())
    }

    func testSequenceGapsAreVisible() throws {
        // A gap in the sequence numbers means a missed range; the resolver keeps both sides,
        // callers can detect the hole from the sequence numbers.
        let (events, _) = HistoryTimeline.resolve(try [ref(1, hour: 8), meal(2, 10), meal(9, 20)], reference: nil, timeZone: utc)
        let seqs = events.map(\.sequence)
        XCTAssertEqual(seqs, [2, 9])
        XCTAssertTrue(zip(seqs.dropFirst(), seqs).contains { $0 - $1 > 1 })
    }

    func testInvalidReferenceDateIsIgnored() throws {
        let bad = try rec(0xF00E, 1, 0, [0x3c, 0xea, 0x07, 13, 40, 8, 0, 0])   // month 13, day 40
        let (events, ref0) = HistoryTimeline.resolve([bad, try meal(2, 5)], reference: nil, timeZone: utc)
        XCTAssertTrue(events.isEmpty)
        XCTAssertNil(ref0)
    }

    func testSensorGlucoseRangeFilter() throws {
        func sg(_ v: UInt16) throws -> HistoryEvent {
            try rec(0xF00C, 1, 0, [0, 0, UInt8(v & 0xFF), UInt8(v >> 8), 0, 0, 0, 0]).event
        }
        XCTAssertEqual(try sg(39), .sensorGlucose(mgdl: nil))
        XCTAssertEqual(try sg(40), .sensorGlucose(mgdl: 40))
        XCTAssertEqual(try sg(400), .sensorGlucose(mgdl: 400))
        XCTAssertEqual(try sg(401), .sensorGlucose(mgdl: nil))
        XCTAssertEqual(try sg(0x0301), .sensorGlucose(mgdl: nil))
    }
}

final class CGMPlausibilityTests: XCTestCase {
    func testSensorClockIgnoresSmallDeviationAndRoundsToQuarterHours() {
        let start = Date(timeIntervalSince1970: 1_760_000_000)
        let now = start.addingTimeInterval(1000 * 60)
        XCTAssertNil(SensorClock.shift(sessionStart: start, offsetMinutes: 1000, now: now))
        XCTAssertNil(SensorClock.shift(sessionStart: start, offsetMinutes: 1000 - 5, now: now))
        XCTAssertEqual(SensorClock.shift(sessionStart: start, offsetMinutes: 1000 - 60, now: now), 3600)
        XCTAssertEqual(SensorClock.shift(sessionStart: start, offsetMinutes: 1000 + 60, now: now), -3600)
        XCTAssertNil(SensorClock.shift(sessionStart: start, offsetMinutes: 1000 - 52, now: now), "52 min is no quarter-hour multiple")
    }

    func testPumpAlarmTableIsComplete() {
        for c in PumpAlarmCategory.allCases { XCTAssertFalse(c.title.isEmpty) }
        let unknown = PumpAlarms.info(for: 0x0FFF)
        XCTAssertEqual(unknown.category, .other)
        XCTAssertTrue(unknown.title.contains("0FFF"))
        XCTAssertFalse(PumpAlarms.info(for: 0x0007).title.isEmpty)
    }
}
