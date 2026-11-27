// SPDX-License-Identifier: GPL-3.0-or-later
import XCTest
import MiniMedKit
@testable import OpenMinipump

final class UnitConversionTests: XCTestCase {
    override func setUp() { Fixtures.useGerman() }
    override func tearDown() { Prefs.defaults.removeObject(forKey: Prefs.languageKey) }

    func testMgdlFormat() {
        XCTAssertEqual(GlucoseUnit.mgdl.format(142), "142")
        XCTAssertEqual(GlucoseUnit.mgdl.label, "mg/dL")
        XCTAssertEqual(GlucoseUnit.mmol.label, "mmol/L")
    }

    func testMmolFormatUsesGermanDecimalComma() {
        XCTAssertEqual(GlucoseUnit.mmol.format(90), "5,0")
        XCTAssertEqual(GlucoseUnit.mmol.format(180), "10,0")
        XCTAssertEqual(GlucoseUnit.mmol.format(54), "3,0")
    }

    func testMmolRoundTripStaysWithinOneMgdl() {
        for mgdl in 40...400 {
            let text = GlucoseUnit.mmol.format(mgdl).replacingOccurrences(of: ",", with: ".")
            let back = Double(text)! * 18.0182
            XCTAssertEqual(back, Double(mgdl), accuracy: 1.0, "\(mgdl)")
        }
    }

    func testMmolIsMonotonic() {
        var last = 0.0
        for mgdl in 40...400 {
            let v = Double(GlucoseUnit.mmol.format(mgdl).replacingOccurrences(of: ",", with: "."))!
            XCTAssertGreaterThanOrEqual(v, last); last = v
        }
    }

    func testDeltaFormats() {
        XCTAssertEqual(GlucoseUnit.mgdl.formatDelta(nil), "")
        XCTAssertEqual(GlucoseUnit.mgdl.formatDelta(0), "±0")
        XCTAssertEqual(GlucoseUnit.mgdl.formatDelta(7), "+7")
        XCTAssertEqual(GlucoseUnit.mgdl.formatDelta(-7), "-7")
        XCTAssertEqual(formatDelta(7), "+7"); XCTAssertEqual(formatDelta(-3), "-3"); XCTAssertEqual(formatDelta(0), "±0")
        XCTAssertEqual(formatDelta(nil), "")
        XCTAssertEqual(GlucoseUnit.mmol.formatDelta(0), "±0,0")
        XCTAssertEqual(GlucoseUnit.mmol.formatDelta(1), "±0,1".replacingOccurrences(of: "±", with: "+"), "1 mg/dL = 0.055 mmol/L")
        XCTAssertEqual(GlucoseUnit.mmol.formatDelta(18), "+1,0")
        XCTAssertEqual(GlucoseUnit.mmol.formatDelta(-18), "-1,0")
    }

    func testMmolDeltaNeverShowsMinusZero() {
        for d in -2...2 {
            let t = GlucoseUnit.mmol.formatDelta(d)
            XCTAssertFalse(t.contains("-0,0") || t.contains("+0,0"), "\(d) -> \(t)")
        }
    }

    func testInsulinUnitsText() {
        XCTAssertEqual(insulinUnits(1.25, 2), "1,25 IE")
        Prefs.defaults.set("en", forKey: Prefs.languageKey)
        XCTAssertEqual(insulinUnits(1.25, 2), "1.25 U")
    }
}

final class TrendArrowTests: XCTestCase {
    func testArrowCounts() {
        XCTAssertEqual(TrendArrow.text(nil), "")
        XCTAssertEqual(TrendArrow.text(0), "→")
        XCTAssertEqual(TrendArrow.text(0.99), "→")
        XCTAssertEqual(TrendArrow.text(-0.99), "→")
        XCTAssertEqual(TrendArrow.text(1), "↑")
        XCTAssertEqual(TrendArrow.text(-1), "↓")
        XCTAssertEqual(TrendArrow.text(2.5), "↑↑")
        XCTAssertEqual(TrendArrow.text(-3), "↓↓↓")
        XCTAssertEqual(TrendArrow.text(12), "↑↑↑", "at most three arrows")
    }

    func testArrowsAgreeWithNightscoutDirection() {
        for rate in stride(from: -4.0, through: 4.0, by: 0.05) {
            let arrows = TrendArrow.text(rate)
            let dir = Nightscout.direction(forRate: rate).name
            let expected: String
            switch arrows.count {
            case 0...1 where arrows == "→": expected = "Flat"
            case 1: expected = rate > 0 ? "SingleUp" : "SingleDown"
            default: expected = rate > 0 ? "DoubleUp" : "DoubleDown"
            }
            XCTAssertEqual(dir, expected, "rate \(rate): \(arrows)")
        }
    }
}

final class WidgetSnapshotTests: XCTestCase {
    private func snap(_ pts: [(Double, Int)]) -> WidgetSnapshot {
        WidgetSnapshot(points: pts.map { .init(date: Fixtures.t0.addingTimeInterval(-$0.0 * 60), mgdl: $0.1) },
                       trendRate: nil, iob: nil, updatedAt: Fixtures.t0)
    }

    func testDeltaNeedsTwoClosePoints() {
        XCTAssertNil(snap([(0, 100)]).delta)
        XCTAssertNil(WidgetSnapshot(points: [], trendRate: nil, iob: nil, updatedAt: Fixtures.t0).delta)
        XCTAssertEqual(snap([(5, 100), (0, 112)]).delta, 12)
        XCTAssertEqual(snap([(5, 100), (0, 90)]).delta, -10)
        XCTAssertNil(snap([(20, 100), (0, 112)]).delta, "a gap over 15 min gives no delta")
    }

    func testLatestIsLastPoint() {
        XCTAssertEqual(snap([(5, 100), (0, 112)]).latest?.mgdl, 112)
    }

    func testCodableRoundTripAndOldFilesWithoutNewFields() throws {
        let s = WidgetSnapshot.placeholder
        let back = try JSONDecoder().decode(WidgetSnapshot.self, from: JSONEncoder().encode(s))
        XCTAssertEqual(back, s)
        let old = #"{"points":[{"date":0,"mgdl":100}],"updatedAt":0}"#
        let decoded = try JSONDecoder().decode(WidgetSnapshot.self, from: Data(old.utf8))
        XCTAssertNil(decoded.reservoir); XCTAssertNil(decoded.mode)
    }

    func testPlaceholderIsPlausible() {
        let p = WidgetSnapshot.placeholder
        XCTAssertEqual(p.points.count, 36)
        XCTAssertTrue(p.points.allSatisfy { (40...400).contains($0.mgdl) })
        XCTAssertEqual(p.points.map(\.date), p.points.map(\.date).sorted())
        XCTAssertTrue((0...100).contains(p.pumpBattery ?? -1))
    }
}

final class LiveActivityCurveTests: XCTestCase {
    private func points(_ n: Int) -> [WidgetSnapshot.Point] {
        (0..<n).map { .init(date: Fixtures.t0.addingTimeInterval(Double($0 - (n - 1)) * 300), mgdl: 100 + $0) }
    }

    func testCurveCoversThreeHoursOldestFirst() {
        let c = GlucoseActivityAttributes.curve(from: points(72), latest: Fixtures.t0)
        XCTAssertEqual(c.count, 37)            // 0 ... 180 min in 5 min steps
        XCTAssertEqual(c.first?.m, 180)
        XCTAssertEqual(c.last?.m, 0)
        XCTAssertEqual(c.last?.v, 171)
        XCTAssertEqual(c.map(\.m), c.map(\.m).sorted(by: >))
        XCTAssertTrue(c.allSatisfy { $0.m >= 0 && $0.m <= 180 })
    }

    func testCustomHoursAndEmpty() {
        XCTAssertEqual(GlucoseActivityAttributes.curve(from: points(72), latest: Fixtures.t0, hours: 1).count, 13)
        XCTAssertTrue(GlucoseActivityAttributes.curve(from: [], latest: Fixtures.t0).isEmpty)
    }

    func testContentStateStaysUnderFourKilobytes() throws {
        let state = GlucoseActivityAttributes.ContentState(
            mgdl: 171, trendRate: 0.4, delta: 3, date: Fixtures.t0, iob: 1.2,
            curve: GlucoseActivityAttributes.curve(from: points(72), latest: Fixtures.t0))
        let data = try JSONEncoder().encode(state)
        XCTAssertLessThan(data.count, 4096, "Live Activity updates may be 4 KB at most (is \(data.count) B)")
        XCTAssertEqual(try JSONDecoder().decode(GlucoseActivityAttributes.ContentState.self, from: data), state)
    }
}
