// SPDX-License-Identifier: GPL-3.0-or-later
import XCTest
@testable import MiniMedKit

final class HistoryTests: XCTestCase {
    /// Builds a record: type (u16), sequence (u32), relative offset (u16), payload.
    private func record(_ type: UInt16, _ seq: UInt32, _ offset: UInt16, _ payloadHex: String) -> [UInt8] {
        [UInt8(type & 0xFF), UInt8(type >> 8)]
            + (0..<4).map { UInt8((seq >> (8 * UInt32($0))) & 0xFF) }
            + [UInt8(offset & 0xFF), UInt8(offset >> 8)]
            + [UInt8](hex: payloadHex)!
    }

    func testParsesEvents() throws {
        // Reference time 2026-10-15 08:30:00, reason periodic (0x3c)
        let ref = try HistoryRecord(record(0xF00E, 100, 0, "3c" + "ea07" + "0a" + "0f" + "08" + "1e" + "00"))
        guard case .referenceTime(let c) = ref.event else { return XCTFail() }
        XCTAssertEqual(c.year, 2026); XCTAssertEqual(c.hour, 8); XCTAssertEqual(c.minute, 30)

        // Bolus delivered: id 7, fast 2.5 U (f32 0xff000019 = 25e-1), ext 0, duration 0
        let bolus = try HistoryRecord(record(0x0069, 101, 60, "0700" + "33" + "190000ff" + "00000000" + "0000"))
        XCTAssertEqual(bolus.event, .bolusDelivered(id: 7, fastUnits: 2.5, extendedUnits: 0, durationMinutes: 0))

        // Auto basal 0.05 U (f32: m=5, e=-2 → 0xfe000005)
        XCTAssertEqual(try HistoryRecord(record(0xF001, 102, 120, "01" + "050000fe")).event, .autoBasal(units: 0.05))

        // Meal 45 g (SFLOAT 0x002d)
        XCTAssertEqual(try HistoryRecord(record(0xF005, 103, 130, "2d00")).event, .meal(grams: 45))

        // BG 120 mg/dL = 0.0012 kg/L → SFLOAT m=12, e=-4 → 0xC00C
        XCTAssertEqual(try HistoryRecord(record(0xF007, 104, 140, "0000" + "0cc0")).event, .bgReading(mgdl: 120))
        XCTAssertEqual(try HistoryRecord(record(0xF008, 105, 150, "0000" + "0cc0")).event, .calibration(mgdl: 120, accepted: true))

        // SG 142 and special value 0x0301 (sensor starting)
        XCTAssertEqual(try HistoryRecord(record(0xF00C, 106, 160, "0000" + "8e00" + "0000" + "0000")).event, .sensorGlucose(mgdl: 142))
        XCTAssertEqual(try HistoryRecord(record(0xF00C, 107, 170, "0000" + "0103" + "0000" + "0000")).event, .sensorGlucose(mgdl: nil))

        // Basal rate changed with context byte
        XCTAssertEqual(try HistoryRecord(record(0x0099, 108, 180, "01" + "00000000" + "050000fe" + "55")).event,
                       .basalRateChanged(oldUnitsPerHour: 0, newUnitsPerHour: 0.05))

        XCTAssertEqual(try HistoryRecord(record(0x1234, 109, 0, "aabb")).event, .other(type: 0x1234))
        XCTAssertThrowsError(try HistoryRecord(record(0xF005, 110, 0, "2d0000")))
    }

    func testTimelineUsesLatestReference() throws {
        let utc = TimeZone(identifier: "UTC")!
        let records = try [
            HistoryRecord(record(0xF001, 99, 30, "01050000fe")),                       // before any reference → dropped
            HistoryRecord(record(0xF00E, 100, 0, "3cea070a0f081e00")),                  // 08:30:00
            HistoryRecord(record(0xF005, 101, 300, "2d00")),                            // 08:35:00
            HistoryRecord(record(0xF00E, 102, 0, "3cea070a0f0a0000")),                  // 10:00:00
            HistoryRecord(record(0xF001, 103, 90, "01050000fe")),                       // 10:01:30
        ]
        let (events, ref) = HistoryTimeline.resolve(records.shuffled(), reference: nil, timeZone: utc)
        XCTAssertEqual(events.map(\.sequence), [101, 103])
        let f = ISO8601DateFormatter()
        XCTAssertEqual(f.string(from: events[0].date), "2026-10-15T08:35:00Z")
        XCTAssertEqual(f.string(from: events[1].date), "2026-10-15T10:01:30Z")
        XCTAssertEqual(ref?.sequence, 102)

        // Continuing with a stored reference
        let more = try [HistoryRecord(record(0xF005, 104, 600, "1400"))]
        let (next, _) = HistoryTimeline.resolve(more, reference: ref, timeZone: utc)
        XCTAssertEqual(f.string(from: next[0].date), "2026-10-15T10:10:00Z")
    }
}

final class TreatmentTests: XCTestCase {
    func testMapping() {
        let d = Date(timeIntervalSince1970: 1_760_000_000)
        XCTAssertEqual(Treatment(TimedHistoryEvent(sequence: 1, date: d, event: .meal(grams: 30)))?.kind, .carbs)
        XCTAssertNil(Treatment(TimedHistoryEvent(sequence: 2, date: d, event: .calibration(mgdl: 100, accepted: false))))
        XCTAssertNil(Treatment(TimedHistoryEvent(sequence: 3, date: d, event: .sensorGlucose(mgdl: 120))))

        let bolus = Treatment(id: 4, date: d, kind: .bolus, value: 2.5)
        let ns = Nightscout.treatment(bolus)!
        XCTAssertEqual(ns["eventType"] as? String, "Correction Bolus")
        XCTAssertEqual((ns["insulin"] as? NSNumber)?.doubleValue, 2.5)
        XCTAssertTrue(JSONSerialization.isValidJSONObject(ns))
        XCTAssertNil(Nightscout.treatment(Treatment(id: 5, date: d, kind: .autoBasal, value: 0.05)))
        XCTAssertEqual(Nightscout.treatment(Treatment(id: 5, date: d, kind: .autoBasal, value: 0.05), includeAutoBasal: true)?["type"] as? String, "SMB")
        XCTAssertEqual((Nightscout.treatment(Treatment(id: 6, date: d, kind: .carbs, value: 40))?["carbs"] as? NSNumber)?.doubleValue, 40)
    }
}

final class BolusClassificationTests: XCTestCase {
    func testAutoCorrectionUsesActivationType() throws {
        let d = Date(timeIntervalSince1970: 1_760_000_000)
        // P2: flags 0x03 (activation + end reason), start offset 0, activation, end reason 0x33
        let p2Auto = try HistoryRecord([0x96, 0x00, 11, 0, 0, 0, 0, 0] + [0x03, 0, 0, 0, 0, 0x5A, 0x33])
        let p2Wizard = try HistoryRecord([0x96, 0x00, 21, 0, 0, 0, 0, 0] + [0x03, 0, 0, 0, 0, 0x3C, 0x33])
        XCTAssertEqual(p2Auto.event, .bolusDeliveredDetails(activationType: 0x5A))
        let events = [
            TimedHistoryEvent(sequence: 10, date: d, event: .bolusDelivered(id: 1, fastUnits: 0.4, extendedUnits: 0, durationMinutes: 0)),
            TimedHistoryEvent(sequence: 11, date: d, event: p2Auto.event),
            TimedHistoryEvent(sequence: 20, date: d, event: .bolusDelivered(id: 2, fastUnits: 5, extendedUnits: 0, durationMinutes: 0)),
            TimedHistoryEvent(sequence: 21, date: d, event: p2Wizard.event),
            TimedHistoryEvent(sequence: 30, date: d, event: .bolusDelivered(id: 3, fastUnits: 1, extendedUnits: 0, durationMinutes: 0)),
        ]
        let t = Treatment.from(events)
        XCTAssertEqual(t.map(\.kind), [.autoCorrection, .bolus, .bolus])
        XCTAssertEqual(Nightscout.treatment(t[0])?["automatic"] as? Bool, true)
    }
}
