// SPDX-License-Identifier: GPL-3.0-or-later
// Parser vectors: OpenMinimed PythonPumpConnector (real 780G payloads, GPL-3.0).
import XCTest
@testable import MiniMedKit

final class ProtocolTests: XCTestCase {
    func testE2ECRC() {
        XCTAssertTrue(Checksums.hasValidE2ECRC([UInt8](hex: "ea07031c0a1f2a80ff0873")!))
        XCTAssertFalse(Checksums.hasValidE2ECRC([UInt8](hex: "ea07031c0a1f2a80ff0874")!))
    }

    func testMedFloat() {
        XCTAssertEqual(MedFloat.decode16(0xF90F), -177.7)
        XCTAssertEqual(MedFloat.decode32(0xF826_25A0), 0.025)
    }

    func testCGMMeasurement() throws {
        let m = try CGMMeasurement([UInt8](hex: "0ec3f900f40b000074e00a00e0f1")!)
        XCTAssertEqual(m.glucoseMgdl, 249)
        XCTAssertEqual(m.timeOffsetMinutes, 3060)
        XCTAssertEqual(m.trendMgdlPerMin, 1.16)
        XCTAssertEqual(m.quality, 10)

        let m2 = try CGMMeasurement([UInt8](hex: "0ec38d00e803000010e00a00d9af")!)
        XCTAssertEqual(m2.glucoseMgdl, 141)
        XCTAssertEqual(m2.timeOffsetMinutes, 1000)

        XCTAssertThrowsError(try CGMMeasurement([UInt8](hex: "0ec3f900f40b000074e00a00e0f2")!))
    }

    func testSessionStartTime() throws {
        let raw = [UInt8](hex: "ea0704040c323680ff")!
        let crc = Checksums.e2eCRC(raw)
        let t = try CGMSessionStartTime(raw + [UInt8(crc & 0xFF), UInt8(crc >> 8)])
        XCTAssertEqual(t.components.year, 2026)
        XCTAssertEqual(t.components.hour, 12)
        XCTAssertNil(t.timeZoneOffsetMinutes)
        let utc = TimeZone(identifier: "UTC")!
        XCTAssertEqual(t.date(fallbackTimeZone: utc)?.timeIntervalSince1970, 1775307054)
    }

    func testPumpStatus() throws {
        let s = try PumpStatus([UInt8](hex: "5596e80d28fb010300")!)
        XCTAssertEqual(s.therapyControlState, .run)
        XCTAssertEqual(s.operationalState, .ready)
        XCTAssertEqual(s.reservoirUnits, 26.25, accuracy: 0.0001) // 0xfb280de8 = 2625000e-5
        XCTAssertTrue(s.reservoirAttached)
        XCTAssertTrue(s.sensorOn)
        XCTAssertFalse(s.isSuspended)
    }

    func testInsulinOnBoard() throws {
        let iob = try InsulinOnBoard([UInt8](hex: "fc0300c05c15fa")!)
        XCTAssertEqual(iob.units, 1.4, accuracy: 0.0001)
        XCTAssertNil(iob.remainingDurationMinutes)
    }

    func testTimeInRange() throws {
        let tir = try TimeInRange([UInt8](hex: "0204001c024664")!)
        XCTAssertEqual(tir.abovePercent, 28)
        XCTAssertEqual(tir.belowPercent, 2)
        XCTAssertEqual(tir.inRangePercent, 70)
        XCTAssertEqual(tir.smartGuardPercent, 100)
    }

    func testTherapyAlgorithmStates() throws {
        let tas = try TherapyAlgorithmStates([UInt8](hex: "fe0301000200")!)
        XCTAssertEqual(tas.shieldState, .autoBasal)
        XCTAssertEqual(tas.modeDescription, "SmartGuard")
    }

    func testActiveBasal() throws {
        let b = try ActiveBasalRate([UInt8](hex: "6a03000200000000")!)
        XCTAssertEqual(b.profileNumber, 2)
        XCTAssertEqual(b.unitsPerHour, 0)
        XCTAssertNil(b.tempBasalUnitsPerHour)
    }

    func testNightscoutDirections() {
        XCTAssertEqual(Nightscout.direction(forRate: 0.4).name, "Flat")
        XCTAssertEqual(Nightscout.direction(forRate: 1.16).name, "SingleUp")
        XCTAssertEqual(Nightscout.direction(forRate: -2.5).name, "DoubleDown")
        XCTAssertEqual(Nightscout.direction(forRate: nil).name, "NONE")
    }

    func testNightscoutEntryShape() {
        let r = GlucoseReading(date: Date(timeIntervalSince1970: 1_760_000_000), mgdl: 123,
                               trendMgdlPerMin: -1.2, sessionOffsetMinutes: 50)
        let e = Nightscout.entry(r)
        XCTAssertEqual(e["sgv"] as? Int, 123)
        XCTAssertEqual(e["type"] as? String, "sgv")
        XCTAssertEqual(e["date"] as? Int64, 1_760_000_000_000)
        XCTAssertEqual(e["direction"] as? String, "SingleDown")
        XCTAssertTrue(JSONSerialization.isValidJSONObject(e))
    }
}
