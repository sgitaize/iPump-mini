// SPDX-License-Identifier: GPL-3.0-or-later
// Patterns: synthetic glucose days for every rule, boundary cases and ordering.
import XCTest
import MiniMedKit
@testable import OpenMinipump

final class PatternFinderTests: XCTestCase {
    private let cal = SupplyScenario.utc
    /// Day 14 at 23:30 UTC: all fixed windows of "today" are complete.
    private var now: Date { cal.startOfDay(for: SupplyScenario.monday).addingTimeInterval(14 * 86400 + 23.5 * 3600) }
    private var today: Date { cal.startOfDay(for: now) }

    private func finder() -> PatternFinder { PatternFinder(calendar: cal) }

    /// 5-minute values for the last `days` days (including today). `value(dayBack, hour)` gives
    /// mg/dL, nil leaves the value out.
    private func readings(days: Int = 14, _ value: (_ dayBack: Int, _ hour: Double) -> Int? = { _, _ in 110 }) -> [GlucoseReading] {
        var out: [GlucoseReading] = []
        for back in stride(from: days - 1, through: 0, by: -1) {
            let day = cal.date(byAdding: .day, value: -back, to: today)!
            for i in 0..<288 {
                let date = day.addingTimeInterval(Double(i) * 300)
                guard date <= now else { break }
                if let v = value(back, Double(i) / 12) {
                    out.append(GlucoseReading(date: date, mgdl: v, trendMgdlPerMin: 0, sessionOffsetMinutes: nil))
                }
            }
        }
        return out
    }

    private func breakfast(days: Int = 14, hour: Double = 7.5) -> [Treatment] {
        (0..<days).map { back in
            let day = cal.date(byAdding: .day, value: -back, to: today)!
            return Treatment(id: UInt32(100 + back), date: day.addingTimeInterval(hour * 3600), kind: .carbs, value: 40)
        }
    }

    private func hints(_ r: [GlucoseReading], _ t: [Treatment] = [], _ f: PatternFinder? = nil) -> [PatternHint] {
        (f ?? finder()).hints(readings: r, treatments: t, now: now)
    }

    // MARK: High after meals and in fixed windows

    func testHighAfterBreakfastOnFourOfSevenDays() {
        let high: Set<Int> = [0, 2, 3, 5]
        let r = readings(days: 7) { back, h in high.contains(back) && (8.5..<10.5).contains(h) ? 210 : 110 }
        let result = hints(r, breakfast(days: 7))
        XCTAssertEqual(result.count, 1, "meal window and morning window are one finding")
        XCTAssertEqual(result[0].kind, .high)
        XCTAssertEqual(result[0].window, .afterBreakfast)
        XCTAssertEqual(result[0].days, 4)
        XCTAssertEqual(result[0].ofDays, 7)
        Fixtures.useGerman()
        XCTAssertEqual(result[0].message(unit: .mgdl), "Nach dem Frühstück an 4 von 7 Tagen über 180")
    }

    func testHighMinimumDaysBoundary() {
        for affected in 0...5 {
            let high = Set(0..<affected)
            let r = readings(days: 7) { back, h in high.contains(back) && (13.0..<14.0).contains(h) ? 200 : 110 }   // afternoon window
            let got = hints(r).filter { $0.kind == .high }
            XCTAssertEqual(got.isEmpty, affected < 3, "\(affected) affected days of 7")
            if affected >= 3 { XCTAssertEqual(got.first?.days, affected) }
        }
    }

    func testValueExactlyAtTheLimitIsNotHigh() {
        let r = readings(days: 7) { _, h in (14..<18).contains(h) ? 180 : 110 }
        XCTAssertTrue(hints(r).isEmpty)
        let r2 = readings(days: 7) { _, h in (14..<18).contains(h) ? 181 : 110 }
        XCTAssertEqual(hints(r2).first?.kind, .high)
    }

    func testSingleSpikeDoesNotCount() {
        // Fewer than 3 values above the limit in a window: no "affected day".
        let r = readings(days: 7) { _, h in (15.0..<15.1).contains(h) ? 250 : 110 }
        XCTAssertTrue(hints(r).isEmpty)
    }

    func testCustomLimitsAreUsed() {
        let r = readings(days: 7) { _, h in (14..<18).contains(h) ? 160 : 100 }
        XCTAssertTrue(hints(r).isEmpty)
        var f = finder(); f.high = 150
        XCTAssertEqual(hints(r, [], f).first?.limit, 150)
    }

    // MARK: Low

    func testLowAtNightOnThreeDays() {
        let low: Set<Int> = [1, 4, 6]
        let r = readings(days: 7) { back, h in low.contains(back) && (2..<3.5).contains(h) ? 58 : 110 }
        let result = hints(r)
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].kind, .low)
        XCTAssertEqual(result[0].window, .night)
        XCTAssertEqual(result[0].days, 3)
        Fixtures.useGerman()
        XCTAssertEqual(result[0].message(unit: .mgdl), "Nachts an 3 von 7 Tagen unter 70")
        XCTAssertTrue(result[0].message(unit: .mmol).hasSuffix("unter 3,9"), result[0].message(unit: .mmol))
    }

    func testLowBoundaries() {
        // exactly 70 is not below
        XCTAssertTrue(hints(readings(days: 7) { _, h in h < 4 ? 70 : 110 }).isEmpty)
        // 69 for two values on two days: hint; on one day: none
        func nights(_ days: Set<Int>) -> [PatternHint] {
            hints(readings(days: 7) { back, h in days.contains(back) && (3.0..<3.17).contains(h) ? 69 : 110 })
        }
        XCTAssertEqual(nights([0, 1]).first?.days, 2)
        XCTAssertTrue(nights([0]).isEmpty)
    }

    // MARK: Coverage and minimum days

    func testWindowNeedsEnoughCoverage() {
        // Night has 72 values; with 50 % coverage required exactly 36 are enough, 35 are not.
        func run(_ keep: Int) -> [PatternHint] {
            var f = finder(); f.minCoverage = 0.5
            let r = readings(days: 7) { _, h in h < 6 ? (Int((h * 12).rounded()) < keep ? 60 : nil) : 110 }
            return hints(r, [], f).filter { $0.window == .night }
        }
        XCTAssertEqual(run(36).first?.ofDays, 7)
        XCTAssertTrue(run(35).isEmpty)
    }

    func testDefaultCoverageIs70Percent() {
        // Morning window (6-10 h): 48 values, 34 needed (70 % = 33.6).
        func run(_ keep: Int) -> [PatternHint] {
            let r = readings(days: 7) { _, h in (6..<10).contains(h) ? (Int((h * 12).rounded()) - 72 < keep ? 200 : nil) : 110 }
            return hints(r).filter { $0.window == .morning }
        }
        XCTAssertEqual(run(34).first?.ofDays, 7)
        XCTAssertTrue(run(33).isEmpty)
    }

    func testTooFewDaysWithDataGiveNoHint() {
        for days in 1...4 {
            let r = readings(days: days) { _, h in (14..<18).contains(h) ? 250 : 110 }
            XCTAssertTrue(hints(r).isEmpty, "\(days) days of data")
        }
        XCTAssertFalse(hints(readings(days: 5) { _, h in (14..<18).contains(h) ? 250 : 110 }).isEmpty)
    }

    func testDaysWithMissingWindowDoNotCountAsValid() {
        // 3 of 5 recorded days affected, but two further days have no data in the window.
        let r = readings(days: 7) { back, h in
            if (14..<18).contains(h) { return back >= 5 ? nil : (back < 3 ? 250 : 110) }
            return 110
        }
        let got = hints(r).first
        XCTAssertEqual(got?.days, 3)
        XCTAssertEqual(got?.ofDays, 5)
    }

    func testOldAndFutureValuesAreIgnored() {
        let old = readings(days: 14) { back, h in back >= 10 && (14..<18).contains(h) ? 250 : 110 }
        XCTAssertTrue(hints(old.filter { $0.date < now.addingTimeInterval(-10 * 86400) }).isEmpty)
        var f = finder(); f.lookbackDays = 9
        XCTAssertTrue(hints(old, [], f).isEmpty)
        XCTAssertFalse(hints(old).isEmpty, "inside the 14 days they count")
    }

    // MARK: Time in range vs previous week

    func testRangeChangeToPreviousWeek() {
        var f = finder(); f.minHighDays = 1000   // isolate the comparison
        func run(thisWeekOut: Int, lastWeekOut: Int) -> [PatternHint] {
            let r = readings { back, h in
                guard (11..<14).contains(h) else { return 110 }
                let out = back < 7 ? thisWeekOut : lastWeekOut
                return Int((h * 12).rounded()) - 132 < out ? 200 : 110   // 36 values in the window
            }
            return hints(r, [], f)
        }
        let worse = run(thisWeekOut: 14, lastWeekOut: 7)
        XCTAssertEqual(worse.count, 1)
        XCTAssertEqual(worse[0].kind, .rangeChange)
        XCTAssertEqual(worse[0].window, .noon)
        XCTAssertEqual(worse[0].rangeNow, 61)
        XCTAssertEqual(worse[0].rangeBefore, 81)
        Fixtures.useGerman()
        XCTAssertEqual(worse[0].message(unit: .mgdl), "Mittags: Zeit im Bereich 61 % (Vorwoche 81 %)")
        XCTAssertEqual(run(thisWeekOut: 4, lastWeekOut: 8).count, 1, "better is mentioned neutrally, too: 89 % vs 78 %")
        XCTAssertTrue(run(thisWeekOut: 4, lastWeekOut: 7).isEmpty, "89 % vs 81 % is below 10 points")
        XCTAssertTrue(run(thisWeekOut: 7, lastWeekOut: 7).isEmpty)
    }

    func testRangeChangeNeedsDaysInBothWeeks() {
        var f = finder(); f.minHighDays = 1000
        let r = readings(days: 9) { back, h in (11..<14).contains(h) && back < 7 ? 200 : 110 }   // only 2 days last week
        XCTAssertTrue(hints(r, [], f).isEmpty)
    }

    // MARK: Order and limit

    func testSortedLowBeforeHighBeforeChangeAndLimitedToThree() {
        // night low (2 days), breakfast high (4 days), evening high (6 days), noon high (7 days, also worse than last week)
        let r = readings { back, h in
            if back < 2, (2..<4).contains(h) { return 55 }
            if back < 4, (8.5..<10.5).contains(h) { return 220 }
            if back < 6, (19..<21).contains(h) { return 230 }
            if (11..<14).contains(h) { return back < 7 && Int((h * 12).rounded()) - 132 < 12 ? 200 : 110 }
            return 110
        }
        var f = finder(); f.minHighDays = 3; f.minHighShare = 0.2
        let result = hints(r, breakfast(), f)
        XCTAssertEqual(result.count, 3)
        XCTAssertEqual(result[0].kind, .low)
        XCTAssertEqual(result[0].window, .night)
        // Noon (7 of 14 days) before evening (6 of 14); breakfast (4 of 14) and the change in range are cut off by the limit.
        XCTAssertEqual(result[1].window, .noon)
        XCTAssertEqual(result[2].window, .evening)
        XCTAssertFalse(result.contains { $0.kind == .rangeChange || $0.window == .afterBreakfast })
    }

    func testLowAlwaysBeforeHighEvenIfRarer() {
        let r = readings { back, h in
            if back < 2, (3..<4).contains(h) { return 60 }
            if back < 10, (14..<18).contains(h) { return 240 }
            return 110
        }
        let result = hints(r)
        XCTAssertEqual(Array(result.map(\.kind).prefix(2)), [.low, .high])
    }

    func testOverlappingWindowsOfTheSameKindAreOneFinding() {
        let r = readings { _, h in (8.5..<10.5).contains(h) ? 220 : 110 }
        let result = hints(r, breakfast())
        XCTAssertEqual(result.count, 1)
    }

    // MARK: Meals

    func testMealDetection() {
        // Bolus without carbs counts as a meal, a bolus next to a carbs entry does not double it,
        // entries in the middle of the night are no meal.
        let day = today
        let t = [
            Treatment(id: 1, date: day.addingTimeInterval(12.5 * 3600), kind: .bolus, value: 4),              // lunch via bolus only
            Treatment(id: 2, date: day.addingTimeInterval(18.5 * 3600), kind: .carbs, value: 50),
            Treatment(id: 3, date: day.addingTimeInterval(18.5 * 3600 + 120), kind: .bolus, value: 5),       // same dinner
            Treatment(id: 4, date: day.addingTimeInterval(3 * 3600), kind: .carbs, value: 20),               // night: ignored
            Treatment(id: 5, date: day.addingTimeInterval(7.2 * 3600), kind: .autoCorrection, value: 0.4),   // automatic: not a meal
        ]
        let r = readings(days: 14) { back, h in
            guard back == 0 else { return 110 }
            return (13.5..<15.5).contains(h) || (19.5..<21.5).contains(h) ? 240 : 110
        }
        var f = finder(); f.minHighDays = 1; f.minHighShare = 0; f.minValidDays = 1
        let result = hints(r, t, f).filter { $0.window.isMeal }
        XCTAssertEqual(Set(result.map(\.window)), [.afterLunch, .afterDinner])
    }

    func testNoTreatmentsStillGivesFixedWindows() {
        let r = readings { _, h in (18..<22).contains(h) ? 200 : 110 }
        XCTAssertEqual(hints(r, []).first?.window, .evening)
    }

    func testWordingIsNeutral() {
        Fixtures.useGerman()
        let r = readings { back, h in back < 5 && (14..<18).contains(h) ? 240 : back < 2 && h < 3 ? 50 : 110 }
        for h in hints(r) {
            let text = h.message(unit: .mgdl).lowercased()
            for word in ["sollte", "solltest", "empfehl", "dosis", "erhöh", "reduzier"] {
                XCTAssertFalse(text.contains(word), text)
            }
        }
    }

    func testEmptyInput() {
        XCTAssertTrue(hints([]).isEmpty)
    }
}
