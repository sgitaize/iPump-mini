// SPDX-License-Identifier: GPL-3.0-or-later
// Patterns: simple, traceable statistics over the last 14 days (no AI, no therapy advice).
// Describes only what happened ("on 4 of 7 days above 180"), never what to do about it.
import Foundation
import MiniMedKit

struct PatternHint: Equatable, Identifiable {
    enum Kind: Equatable { case low, high, rangeChange }

    /// Time window of the day (fixed) or after a meal.
    enum Window: Equatable, Hashable {
        case night, morning, noon, afternoon, evening
        case afterBreakfast, afterLunch, afterDinner

        /// Hours of the day (start inclusive, end exclusive) the window covers; for meal windows
        /// the typical time of the meal.
        var hours: ClosedRange<Double> {
            switch self {
            case .night: 0...6
            case .morning: 6...10
            case .noon: 11...14
            case .afternoon: 14...18
            case .evening: 18...22
            case .afterBreakfast: 7...11
            case .afterLunch: 12...16
            case .afterDinner: 18...23
            }
        }
        var isMeal: Bool { self == .afterBreakfast || self == .afterLunch || self == .afterDinner }
    }

    var kind: Kind
    var window: Window
    /// Days on which the condition applied / days that had enough data.
    var days: Int
    var ofDays: Int
    /// Limit (mg/dL) for low / high; time in range in percent (this and previous week) for rangeChange.
    var limit: Int
    var rangeNow: Int = 0
    var rangeBefore: Int = 0

    var id: String { "\(kind)-\(window)" }
}

struct PatternFinder {
    var calendar: Calendar = .current
    var low = 70
    var high = 180
    var lookbackDays = 14
    /// Minimum share of expected 5-minute values in a window for the day to count.
    var minCoverage = 0.7
    var minValidDays = 5
    var minHighDays = 3
    var minHighShare = 0.3
    var minLowDays = 2
    /// Consecutive-agnostic: number of values outside the limit that make a day "affected".
    var minHighReadings = 3
    var minLowReadings = 2
    /// Change of time in range (percentage points) between the weeks that is mentioned.
    var rangeChangePoints = 10
    var maxHints = 3

    private struct Slot { var window: PatternHint.Window; var start: Date; var end: Date }

    private static let fixed: [PatternHint.Window] = [.night, .morning, .noon, .afternoon, .evening]

    func hints(readings: [GlucoseReading], treatments: [Treatment], now: Date) -> [PatternHint] {
        let from = now.addingTimeInterval(-Double(lookbackDays) * 86400)
        let sorted = readings.filter { $0.date >= from && $0.date <= now }.sorted { $0.date < $1.date }
        guard !sorted.isEmpty else { return [] }

        var candidates: [PatternHint] = []

        // Fixed time windows and windows after meals, day by day.
        var slots: [PatternHint.Window: [Slot]] = [:]
        let today = calendar.startOfDay(for: now)
        for back in 0...lookbackDays {
            guard let day = calendar.date(byAdding: .day, value: -back, to: today) else { continue }
            for w in Self.fixed {
                let (a, b) = (w.hours.lowerBound, w.hours.upperBound)
                slots[w, default: []].append(Slot(window: w, start: at(day, a), end: at(day, b)))
            }
        }
        for m in meals(treatments, from: from, now: now) {
            slots[m.window, default: []].append(Slot(window: m.window, start: m.date.addingTimeInterval(3600),
                                                     end: m.date.addingTimeInterval(3 * 3600)))
        }

        for (window, list) in slots {
            var valid = 0, highDays = 0, lowDays = 0
            var tir: [Int: (inRange: Int, total: Int, days: Int)] = [0: (0, 0, 0), 1: (0, 0, 0)]
            for s in list {
                guard s.start >= from, s.end <= now else { continue }
                let values = slice(sorted, in: s.start, s.end)
                let expected = s.end.timeIntervalSince(s.start) / 300
                guard Double(values.count) >= expected * minCoverage else { continue }
                valid += 1
                if values.filter({ $0.mgdl > high }).count >= minHighReadings { highDays += 1 }
                if values.filter({ $0.mgdl < low }).count >= minLowReadings { lowDays += 1 }
                let week = Int(now.timeIntervalSince(s.end) / (7 * 86400))
                if week <= 1 {
                    var t = tir[week]!
                    t.inRange += values.filter { $0.mgdl >= low && $0.mgdl <= high }.count
                    t.total += values.count; t.days += 1
                    tir[week] = t
                }
            }
            guard valid >= minValidDays else { continue }
            if lowDays >= minLowDays {
                candidates.append(PatternHint(kind: .low, window: window, days: lowDays, ofDays: valid, limit: low))
            }
            if highDays >= minHighDays, Double(highDays) / Double(valid) >= minHighShare {
                candidates.append(PatternHint(kind: .high, window: window, days: highDays, ofDays: valid, limit: high))
            }
            if !window.isMeal, let n = tir[0], let p = tir[1], n.days >= 3, p.days >= 3, n.total > 0, p.total > 0 {
                let nowPct = Int((Double(n.inRange) / Double(n.total) * 100).rounded())
                let before = Int((Double(p.inRange) / Double(p.total) * 100).rounded())
                if abs(nowPct - before) >= rangeChangePoints {
                    candidates.append(PatternHint(kind: .rangeChange, window: window, days: n.days, ofDays: n.days,
                                                  limit: 0, rangeNow: nowPct, rangeBefore: before))
                }
            }
        }

        // Relevance: low before high before change; then by share of days and number of days.
        func rank(_ h: PatternHint) -> (Int, Double, Int, Int) {
            let k = h.kind == .low ? 2 : h.kind == .high ? 1 : 0
            let strength = h.kind == .rangeChange ? Double(abs(h.rangeNow - h.rangeBefore)) / 100 : Double(h.days) / Double(max(1, h.ofDays))
            return (k, strength, h.days, h.window.isMeal ? 1 : 0)
        }
        let ordered = candidates.sorted { a, b in
            let (x, y) = (rank(a), rank(b))
            if x.0 != y.0 { return x.0 > y.0 }
            if x.1 != y.1 { return x.1 > y.1 }
            if x.2 != y.2 { return x.2 > y.2 }
            if x.3 != y.3 { return x.3 > y.3 }
            return a.id < b.id
        }

        // Windows of the same kind that overlap in time of day are one finding: keep the stronger one.
        var result: [PatternHint] = []
        for h in ordered where !result.contains(where: { $0.kind == h.kind && overlaps($0.window, h.window) }) {
            result.append(h)
            if result.count == maxHints { break }
        }
        return result
    }

    // MARK: Helpers

    private func overlaps(_ a: PatternHint.Window, _ b: PatternHint.Window) -> Bool {
        a == b || (a.hours.lowerBound < b.hours.upperBound && b.hours.lowerBound < a.hours.upperBound)
    }

    private func at(_ day: Date, _ hour: Double) -> Date {
        calendar.date(byAdding: .minute, value: Int(hour * 60), to: day) ?? day
    }

    private func slice(_ sorted: [GlucoseReading], in a: Date, _ b: Date) -> [GlucoseReading] {
        sorted.filter { $0.date >= a && $0.date < b }
    }

    /// Meals from carbs entries; boluses without carbs nearby count as a meal, too.
    /// Several entries within one hour are one meal.
    private func meals(_ treatments: [Treatment], from: Date, now: Date) -> [(date: Date, window: PatternHint.Window)] {
        let relevant = treatments.filter { $0.date >= from && $0.date <= now }.sorted { $0.date < $1.date }
        let carbs = relevant.filter { $0.kind == .carbs && ($0.value ?? 0) > 0 }
        let boluses = relevant.filter { $0.kind == .bolus && ($0.value ?? 0) > 0 }
            .filter { b in !carbs.contains { abs($0.date.timeIntervalSince(b.date)) <= 600 } }
        var events = (carbs + boluses).sorted { $0.date < $1.date }.map(\.date)
        var merged: [Date] = []
        for d in events where merged.last.map({ d.timeIntervalSince($0) >= 3600 }) ?? true { merged.append(d) }
        events = merged
        return events.compactMap { d in
            let h = Double(calendar.component(.hour, from: d)) + Double(calendar.component(.minute, from: d)) / 60
            switch h {
            case 5..<10.5: return (d, .afterBreakfast)
            case 11..<15: return (d, .afterLunch)
            case 17..<21: return (d, .afterDinner)
            default: return nil
            }
        }
    }
}

// MARK: Texts

extension PatternHint {
    private var windowLabel: String {
        switch window {
        case .night: L10n.tr("Nachts")
        case .morning: L10n.tr("Morgens")
        case .noon: L10n.tr("Mittags")
        case .afternoon: L10n.tr("Nachmittags")
        case .evening: L10n.tr("Abends")
        case .afterBreakfast: L10n.tr("Nach dem Frühstück")
        case .afterLunch: L10n.tr("Nach dem Mittagessen")
        case .afterDinner: L10n.tr("Nach dem Abendessen")
        }
    }

    /// Neutral description, no advice.
    func message(unit: GlucoseUnit) -> String {
        switch kind {
        case .low: L10n.tr("%@ an %d von %d Tagen unter %@", windowLabel, days, ofDays, unit.format(limit))
        case .high: L10n.tr("%@ an %d von %d Tagen über %@", windowLabel, days, ofDays, unit.format(limit))
        case .rangeChange: L10n.tr("%@: Zeit im Bereich %d %% (Vorwoche %d %%)", windowLabel, rangeNow, rangeBefore)
        }
    }
}
