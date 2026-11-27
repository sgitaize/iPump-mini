// SPDX-License-Identifier: GPL-3.0-or-later
// Demo data must look like a real pump: values in range, no gaps, consistent trends and IOB.
import XCTest
import MiniMedKit
@testable import OpenMinipump

@MainActor
final class DemoDataTests: XCTestCase {
    private var store: DataStore!

    override func setUp() async throws {
        store = DataStore(fileURL: Fixtures.tempFile())
        store.loadDemoData()
    }

    func testDemoDoesNotPersist() {
        XCTAssertFalse(store.persistenceEnabled)
    }

    func testReadingsAreInSensorRangeAndFiveMinutesApart() {
        let r = store.readings
        XCTAssertEqual(r.count, 14 * 288)
        XCTAssertTrue(r.allSatisfy { (40...400).contains($0.mgdl) })
        XCTAssertEqual(r.map(\.date), r.map(\.date).sorted())
        for (a, b) in zip(r, r.dropFirst()) {
            XCTAssertEqual(b.date.timeIntervalSince(a.date), 300, accuracy: 0.5, "gap in demo curve")
        }
        XCTAssertLessThanOrEqual(r.last!.date, Date().addingTimeInterval(1))
        XCTAssertGreaterThan(r.last!.date, Date().addingTimeInterval(-60))
    }

    func testTrendMatchesSlopeOfTheCurve() {
        let r = store.readings
        // Compare the stated trend with the actual change per minute between neighbours.
        for (a, b) in zip(r, r.dropFirst()) {
            let slope = Double(b.mgdl - a.mgdl) / 5
            XCTAssertEqual(slope, a.trendMgdlPerMin ?? 0, accuracy: 0.6, "trend \(a.trendMgdlPerMin ?? 0) vs slope \(slope)")
        }
    }

    func testSessionOffsetsAreUniqueAndAscending() {
        let offsets = store.readings.compactMap(\.sessionOffsetMinutes)
        XCTAssertEqual(offsets.count, store.readings.count)
        XCTAssertEqual(Set(offsets).count, offsets.count)
        XCTAssertEqual(offsets, offsets.sorted())
    }

    func testSnapshotIsComplete() {
        let s = store.snapshot
        XCTAssertNotNil(s.status); XCTAssertNotNil(s.iob); XCTAssertNotNil(s.timeInRange)
        XCTAssertNotNil(s.algorithm); XCTAssertNotNil(s.basal)
        XCTAssertTrue((0...100).contains(s.pumpBatteryPercent ?? -1))
        XCTAssertTrue((0...100).contains(s.transmitterBatteryPercent ?? -1))
        XCTAssertGreaterThan(s.sensorEnd ?? .distantPast, Date(), "sensor must not be expired")
        XCTAssertLessThanOrEqual(s.sensorEnd!.timeIntervalSinceNow, 10 * 86400, "sensor life is at most 7 to 10 days")
        let tir = s.timeInRange!
        XCTAssertEqual(Int(tir.abovePercent) + Int(tir.belowPercent) + Int(tir.inRangePercent), 100)
        XCTAssertGreaterThanOrEqual(s.status!.reservoirUnits, 0)
        XCTAssertLessThanOrEqual(s.status!.reservoirUnits, 300)
        XCTAssertTrue(s.status!.sensorOK)
    }

    func testIOBHistoryIsNonNegativeAndEndsAtCurrentIOB() {
        XCTAssertTrue(store.iobHistory.allSatisfy { $0.units >= 0 })
        XCTAssertEqual(store.iobHistory.last!.units, store.snapshot.iob!.units, accuracy: 0.05,
                       "history and current IOB tell different stories")
        XCTAssertEqual(store.iobHistory.map(\.date), store.iobHistory.map(\.date).sorted())
    }

    func testTreatmentsAreUniqueInThePastAndPlausible() {
        let t = store.treatments
        XCTAssertEqual(Set(t.map(\.id)).count, t.count, "duplicate treatment ids")
        XCTAssertTrue(t.allSatisfy { $0.date <= Date() })
        XCTAssertTrue(t.filter { [.bolus, .autoCorrection, .autoBasal, .carbs].contains($0.kind) }.allSatisfy { ($0.value ?? 0) > 0 })
        XCTAssertTrue(t.filter { $0.kind == .bolus }.allSatisfy { $0.value! <= 25 }, "bolus above the usual maximum")
        XCTAssertTrue(t.filter { $0.kind == .calibration }.allSatisfy { (40...400).contains(Int($0.value!)) })
        XCTAssertEqual(t.map(\.date), t.map(\.date).sorted())
    }

    func testDemoSnapshotMapsToNightscout() throws {
        let ds = Nightscout.deviceStatus(store.snapshot, uploaderBattery: 80)
        let pump = try XCTUnwrap(ds["pump"] as? [String: Any])
        XCTAssertEqual(pump["reservoir"] as? Double, 142)
        XCTAssertNotNil(pump["iob"]); XCTAssertNotNil(pump["extended"])
        for t in store.treatments { if let ns = Nightscout.treatment(t, includeAutoBasal: true) { XCTAssertTrue(JSONSerialization.isValidJSONObject(ns)) } }
    }
}

final class DemoModeTests: XCTestCase {
    override func tearDown() { DemoMode.isOn = false }

    func testToggleRoundTrip() {
        DemoMode.isOn = true
        XCTAssertTrue(UserDefaults.standard.bool(forKey: DemoMode.key))
        DemoMode.isOn = false
        XCTAssertFalse(DemoMode.isOn)
    }
}
