// SPDX-License-Identifier: GPL-3.0-or-later
// Supply forecast against synthetic consumption patterns with a known "true" empty time.
import XCTest
import MiniMedKit
@testable import OpenMinipump

/// Deterministic random numbers (SplitMix64) for the generator tests.
struct SeededRandom {
    private var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
    mutating func unit() -> Double { Double(next() >> 11) / Double(1 << 53) }
    mutating func uniform(_ lo: Double, _ hi: Double) -> Double { lo + (hi - lo) * unit() }
}

enum SupplyScenario {
    static var utc: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()
    /// Monday 2025-10-06 00:00 UTC.
    static let monday = Date(timeIntervalSince1970: 1_759_708_800)

    struct Setup {
        var kind: SupplyKind = .reservoir
        /// Consumption per hour (units or percent) at a point in time; the truth.
        var rate: (Date) -> Double
        /// Consumption after "now" (default: same function).
        var futureRate: ((Date) -> Double)?
        var now = SupplyScenario.monday.addingTimeInterval((8 * 24 + 9.5) * 3600)   // Tuesday 09:30, 8.4 days in
        var historyDays = 8.0
        var levelNow = 100.0
        /// Reservoir changes / battery swaps, in days before `now`. The level before was `levelBeforeChange`.
        var changes: [Double] = []
        var levelBeforeChange = 10.0
        var noise = 0.0
        /// Glitches: single samples that read too low by this amount (at these ages in days).
        var glitches: [(daysAgo: Double, drop: Double)] = []
        /// Missing periods (days ago start, hours long).
        var gaps: [(daysAgo: Double, hours: Double)] = []
        var quantize = false
        var seed: UInt64 = 1
    }

    /// Builds the history backwards from the current level (so the level now is exactly known).
    static func samples(_ s: Setup) -> [SupplySample] {
        var rng = SeededRandom(seed: s.seed)
        let step = 900.0
        let n = Int(s.historyDays * 86400 / step)
        var level = s.levelNow
        var out: [SupplySample] = []
        for i in 0...n {
            let date = s.now.addingTimeInterval(-Double(i) * step)
            let age = Double(i) * step / 86400
            var value = level
            for g in s.glitches where abs(g.daysAgo - age) < step / 86400 / 2 { value -= g.drop }
            value += s.noise * (rng.unit() * 2 - 1)
            if s.quantize { value = value.rounded() }
            let inGap = s.gaps.contains { age >= $0.daysAgo && age <= $0.daysAgo + $0.hours / 24 }
            if !inGap {
                out.append(SupplySample(date: date,
                                        reservoir: s.kind == .reservoir ? max(0, value) : nil,
                                        battery: s.kind == .battery ? max(0, value) : nil))
            }
            // Consumption in the interval before `date` (backwards: the level was higher).
            level += s.rate(date.addingTimeInterval(-step / 2)) * step / 3600
            if s.changes.contains(where: { age < $0 && age + step / 86400 >= $0 }) { level = s.levelBeforeChange }
        }
        return out.reversed()
    }

    /// True time at which `threshold` is reached, simulated minute by minute.
    static func truth(_ s: Setup, threshold: Double) -> Date {
        var level = s.levelNow
        var t = s.now
        let future = s.futureRate ?? s.rate
        while level > threshold {
            level -= future(t.addingTimeInterval(30)) / 60
            t = t.addingTimeInterval(60)
            if t.timeIntervalSince(s.now) > 40 * 86400 { break }
        }
        return t
    }

    static func forecaster(halfLife: Double = 2) -> SupplyForecaster {
        var f = SupplyForecaster(calendar: utc)
        f.halfLifeDays = halfLife
        return f
    }

    /// Relative error of the predicted time against the true one, in relation to the remaining time.
    static func error(_ s: Setup, threshold: Double = 0, forecaster f: SupplyForecaster = forecaster(), label: String = #function) -> (error: Double, prediction: SupplyPrediction?) {
        let outcome = f.forecast(kind: s.kind, samples: samples(s), now: s.now)
        guard case let .ready(p) = outcome else { print("[forecast] not ready: \(outcome)"); return (.infinity, nil) }
        let est = threshold == 0 ? p.empty : p.alarm
        guard let est else { return (.infinity, p) }
        let truth = truth(s, threshold: threshold)
        let remaining = truth.timeIntervalSince(s.now)
        let err = abs(est.date.timeIntervalSince(truth)) / remaining
        print(String(format: "[forecast] %@ threshold %.0f: error %.2f %% of %.1f h remaining, range ± %.1f h", label, threshold, err * 100, remaining / 3600, est.margin / 3600))
        return (err, p)
    }

    static func hour(_ date: Date) -> Int { utc.component(.hour, from: date) }
    static func isWeekend(_ date: Date) -> Bool { let w = utc.component(.weekday, from: date); return w == 1 || w == 7 }
}

final class SupplyForecastTests: XCTestCase {
    typealias S = SupplyScenario

    private func meals(_ d: Date) -> Double { [7, 12, 18].contains(S.hour(d)) ? 2.5 : 0 }

    // MARK: Pattern by pattern (tolerance 10 % of the remaining time)

    func testConstantConsumption() {
        let s = S.Setup(rate: { _ in 1.5 })
        for threshold in [0.0, 20] {
            let r = S.error(s, threshold: threshold)
            XCTAssertLessThan(r.error, 0.02, "constant, threshold \(threshold)")
        }
    }

    func testDayNightProfile() {
        let s = S.Setup(rate: { d in (0..<6).contains(S.hour(d)) ? 0.4 : 1.3 + self.meals(d) })
        let r = S.error(s)
        XCTAssertLessThan(r.error, 0.05)
        // The simulation must follow the time of day: starting at 09:30 the range has to be tight.
        XCTAssertLessThan(r.prediction!.empty!.margin, 12 * 3600)
    }

    func testWeekendDiffersFromWeekdays() {
        // Remaining supply runs into the weekend; the weekend profile has to be used.
        var s = S.Setup(rate: { d in S.isWeekend(d) ? 2.4 : 1.0 })
        s.levelNow = 90
        let split = S.error(s)
        XCTAssertLessThan(split.error, 0.08, "weekday/weekend separated")
        // Control: without separation (too little weekend data) it would be clearly off; the
        // forecaster uses the weekend profile as soon as 2 weekend days are known.
        XCTAssertTrue(S.forecaster().profile(kind: .reservoir, samples: S.samples(s), now: s.now)!.separated)
    }

    func testReservoirChangeInTheMiddleIsNotCountedAsConsumption() {
        var s = S.Setup(rate: { d in 1.2 + self.meals(d) / 2 })
        s.changes = [3.2, 6.1]
        s.levelBeforeChange = 8
        let r = S.error(s)
        XCTAssertLessThan(r.error, 0.04)
    }

    func testNoiseAndOutliers() {
        var s = S.Setup(rate: { d in 1.4 + self.meals(d) / 2 })
        s.noise = 0.08
        s.glitches = [(1.3, 60), (2.6, 120), (4.9, 40), (6.2, 90)]
        let r = S.error(s)
        XCTAssertLessThan(r.error, 0.10)
    }

    func testDataGaps() {
        var s = S.Setup(rate: { d in (0..<6).contains(S.hour(d)) ? 0.6 : 1.6 })
        s.gaps = [(0.5, 5), (2.0, 10), (4.2, 26), (6.5, 7)]
        let r = S.error(s)
        XCTAssertLessThan(r.error, 0.10)
        XCTAssertGreaterThan(r.prediction!.daysOfData, 4)
    }

    func testRecentBehaviourChangeCountsMore() {
        // 5 days at 1.0 U/h, then 3 days at 2.0 U/h (and it stays that way).
        let change = S.monday.addingTimeInterval(5 * 86400)
        var s = S.Setup(rate: { $0 < change ? 1.0 : 2.0 })
        s.futureRate = { _ in 2.0 }
        s.levelNow = 120
        let weighted = S.error(s)
        let uniform = S.error(s, forecaster: S.forecaster(halfLife: 1000))
        print("[forecast] behaviour change: weighted \(weighted.error), uniform \(uniform.error)")
        XCTAssertLessThan(weighted.error, 0.30)
        XCTAssertLessThan(weighted.error, uniform.error, "recent days must weigh more than old ones")
    }

    func testTooLittleDataGivesNoForecast() {
        var s = S.Setup(rate: { _ in 1.5 })
        s.historyDays = 1.4
        let f = S.forecaster()
        guard case let .learning(days, needed) = f.forecast(kind: .reservoir, samples: S.samples(s), now: s.now) else {
            return XCTFail("expected 'learning'")
        }
        XCTAssertEqual(days, 1.4, accuracy: 0.1)
        XCTAssertEqual(needed, 2)
        s.historyDays = 2.2
        guard case .ready = f.forecast(kind: .reservoir, samples: S.samples(s), now: s.now) else {
            return XCTFail("2.2 days are enough")
        }
    }

    func testBatteryCurve() {
        // About 5 % a day with a slightly higher load in the daytime; a battery swap 3.5 days ago.
        var s = S.Setup(rate: { d in (0..<6).contains(S.hour(d)) ? 0.12 : 0.24 })
        s.kind = .battery
        s.levelNow = 52
        s.changes = [3.5]
        s.levelBeforeChange = 6
        s.quantize = true
        for threshold in [0.0, 10] {
            let r = S.error(s, threshold: threshold)
            XCTAssertLessThan(r.error, 0.10, "battery, threshold \(threshold)")
        }
    }

    // MARK: Behaviour and edge cases

    func testNoNegativeConsumptionAndNoForecastWithoutConsumption() {
        let s = S.Setup(rate: { _ in 0 })
        guard case let .ready(p) = S.forecaster().forecast(kind: .reservoir, samples: S.samples(s), now: s.now) else {
            return XCTFail("expected a result")
        }
        XCTAssertNil(p.empty)
        XCTAssertEqual(p.confidence, 0)
    }

    func testAlreadyBelowAlarmThresholdReportsNow() {
        var s = S.Setup(rate: { _ in 1.5 })
        s.levelNow = 12
        guard case let .ready(p) = S.forecaster().forecast(kind: .reservoir, samples: S.samples(s), now: s.now) else {
            return XCTFail("expected a result")
        }
        XCTAssertEqual(p.alarm!.date, p.basis)
        XCTAssertGreaterThan(p.empty!.date, p.basis)
    }

    func testUncertaintyRangeContainsPredictionAndGrowsWithNoise() {
        var calm = S.Setup(rate: { _ in 1.5 })
        calm.levelNow = 150
        var restless = calm
        restless.rate = { d in 1.5 * (1 + 0.5 * sin(Double(S.utc.ordinality(of: .day, in: .era, for: d)!) * 2.1)) }
        restless.futureRate = { _ in 1.5 }
        let a = S.error(calm).prediction!, b = S.error(restless).prediction!
        for p in [a, b] {
            XCTAssertLessThanOrEqual(p.empty!.earliest, p.empty!.date)
            XCTAssertGreaterThanOrEqual(p.empty!.latest, p.empty!.date)
        }
        XCTAssertGreaterThan(b.empty!.margin, a.empty!.margin)
        XCTAssertGreaterThan(a.confidence, b.confidence)
    }

    func testStaleLastSampleGivesNoData() {
        let s = S.Setup(rate: { _ in 1.5 })
        let samples = S.samples(s)
        XCTAssertEqual(S.forecaster().forecast(kind: .reservoir, samples: samples, now: s.now.addingTimeInterval(20 * 3600)), .noData)
        XCTAssertEqual(S.forecaster().forecast(kind: .battery, samples: samples, now: s.now), .noData)
        XCTAssertEqual(S.forecaster().forecast(kind: .reservoir, samples: [], now: s.now), .noData)
    }

    // MARK: Random profiles with a fixed seed

    func testRandomProfilesWithFixedSeed() {
        var rng = SeededRandom(seed: 20261127)
        var errors: [Double] = []
        for i in 0..<40 {
            let night = rng.uniform(0.3, 1.0), day = rng.uniform(0.8, 2.2)
            let peak = rng.uniform(0, 3), peakHour = Int(rng.uniform(6, 20))
            let weekendFactor = i % 2 == 0 ? 1.0 : rng.uniform(0.6, 1.6)
            let rate: (Date) -> Double = { d in
                let h = S.hour(d)
                let base = h < 6 ? night : day
                return (base + (h == peakHour ? peak : 0)) * (S.isWeekend(d) ? weekendFactor : 1)
            }
            var s = S.Setup(rate: rate)
            s.levelNow = rng.uniform(80, 160)
            s.noise = rng.uniform(0, 0.1)
            s.seed = UInt64(i + 1)
            if i % 3 == 0 { s.changes = [rng.uniform(1.5, 6)] }
            if i % 4 == 0 { s.gaps = [(rng.uniform(0.3, 6), rng.uniform(2, 9))] }
            if i % 5 == 0 { s.glitches = [(rng.uniform(0.5, 7), rng.uniform(30, 100))] }
            errors.append(S.error(s).error)
        }
        let mean = errors.reduce(0, +) / Double(errors.count)
        print("[forecast] random profiles: mean error \(mean), max \(errors.max()!)")
        XCTAssertLessThan(mean, 0.05)
        XCTAssertLessThan(errors.max()!, 0.15)
    }

    // MARK: History

    func testHistoryRecordsEveryFifteenMinutesAndIsCapped() {
        var h: [SupplySample] = []
        let t = Fixtures.t0
        XCTAssertTrue(SupplyHistory.record(SupplySample(date: t, reservoir: 100, battery: 50), into: &h))
        XCTAssertFalse(SupplyHistory.record(SupplySample(date: t.addingTimeInterval(600), reservoir: 99, battery: 50), into: &h))
        XCTAssertTrue(SupplyHistory.record(SupplySample(date: t.addingTimeInterval(900), reservoir: 99, battery: 50), into: &h))
        XCTAssertFalse(SupplyHistory.record(SupplySample(date: t.addingTimeInterval(2000), reservoir: nil, battery: nil), into: &h))
        // 31 days: older than 30 days disappear, count stays capped.
        for i in 1..<(31 * 96 + 50) {
            SupplyHistory.record(SupplySample(date: t.addingTimeInterval(Double(i) * 900 + 1000), reservoir: 50, battery: 50), into: &h)
        }
        XCTAssertLessThanOrEqual(h.count, SupplyHistory.maxSamples)
        XCTAssertGreaterThan(h.first!.date, h.last!.date.addingTimeInterval(-SupplyHistory.retention - 1))
    }

    @MainActor
    func testDataStoreRecordsSupplyOnUpdateAndPersists() {
        let file = Fixtures.tempFile()
        defer { try? FileManager.default.removeItem(at: file) }
        let store = DataStore(fileURL: file)
        let status: PumpStatus = Fixtures.decode(#"{"therapyControlState":85,"operationalState":150,"reservoirUnits":142,"reservoirAttached":true,"sensorConnectivity":1,"sensorMessageState":0}"#)
        store.update { $0.status = status; $0.pumpBatteryPercent = 70 }
        store.update { $0.pumpBatteryPercent = 69 }   // within 15 min: no new sample
        XCTAssertEqual(store.supplyHistory.count, 1)
        XCTAssertEqual(store.supplyHistory[0].reservoir, 142)
        XCTAssertEqual(store.supplyHistory[0].battery, 70)
        XCTAssertEqual(DataStore(fileURL: file).supplyHistory, store.supplyHistory)
    }

    func testFormatting() {
        Fixtures.useGerman()
        XCTAssertEqual(SupplyFormat.margin(3 * 3600), "3 h")
        XCTAssertEqual(SupplyFormat.margin(40 * 60), "40 min")
        XCTAssertEqual(SupplyFormat.margin(3 * 86400), "3 T")
        XCTAssertEqual(SupplyFormat.learning(days: 1.3, needed: 2), "lernt noch (1,3 von 2 Tagen)")
        XCTAssertEqual(SupplyFormat.line(.noData, kind: .reservoir), "Noch keine Werte")
    }
}
