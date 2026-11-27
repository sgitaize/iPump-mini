// SPDX-License-Identifier: GPL-3.0-or-later
// Supply forecast (beta): learns a consumption profile from the stored reservoir and pump
// battery history and simulates when the supply runs out. Pure logic without UI; uses only
// values the app already reads (no additional pump requests).
import Foundation

/// One stored measurement point of the supply history.
struct SupplySample: Codable, Equatable {
    var date: Date
    /// Reservoir content in units, nil when no reservoir is attached or unknown.
    var reservoir: Double?
    /// Pump battery in percent.
    var battery: Double?

    func value(for kind: SupplyKind) -> Double? { kind == .reservoir ? reservoir : battery }
}

enum SupplyKind {
    case reservoir, battery

    /// Level at which a warning is useful (20 U, 10 %).
    var alarmThreshold: Double { self == .reservoir ? 20 : 10 }
    /// A rise above this is a reservoir change or battery swap; smaller rises are noise.
    var changeTolerance: Double { self == .reservoir ? 0.5 : 3 }
    /// Smallest step the value can show (battery: whole percent).
    var resolution: Double { self == .reservoir ? 0.1 : 1 }
}

/// Size limits and sampling interval of the persisted history.
enum SupplyHistory {
    static let minInterval: TimeInterval = 14 * 60
    static let retention: TimeInterval = 30 * 86400
    static let maxSamples = 3000

    /// Appends a sample if the last one is old enough; trims by age and count.
    /// Returns true if the history changed.
    @discardableResult
    static func record(_ sample: SupplySample, into history: inout [SupplySample]) -> Bool {
        guard sample.reservoir != nil || sample.battery != nil else { return false }
        if let last = history.last, sample.date.timeIntervalSince(last.date) < minInterval { return false }
        history.append(sample)
        let cutoff = sample.date.addingTimeInterval(-retention)
        history.removeAll { $0.date < cutoff }
        if history.count > maxSamples { history.removeFirst(history.count - maxSamples) }
        return true
    }
}

struct SupplyEstimate: Equatable {
    var date: Date
    var earliest: Date
    var latest: Date

    /// Half width of the uncertainty range.
    var margin: TimeInterval { latest.timeIntervalSince(earliest) / 2 }
}

struct SupplyPrediction: Equatable {
    var current: Double
    /// Time of the last sample the simulation starts from.
    var basis: Date
    /// Supply at 0 (nil: not within the horizon).
    var empty: SupplyEstimate?
    /// Supply below the alarm threshold (nil: not within the horizon).
    var alarm: SupplyEstimate?
    /// 0...1
    var confidence: Double
    var daysOfData: Double
}

enum SupplyOutcome: Equatable {
    /// No current value.
    case noData
    /// Not enough data yet: `days` covered of `needed`.
    case learning(days: Double, needed: Double)
    case ready(SupplyPrediction)
}

struct SupplyForecaster {
    var calendar: Calendar = .current
    /// Days until a day's weight is halved.
    var halfLifeDays = 2.0
    var minDays = 2.0
    var horizonDays = 30.0
    /// Gaps in the history longer than this are not evaluated.
    var maxGap: TimeInterval = 3 * 3600
    /// The last sample must not be older than this.
    var maxStaleness: TimeInterval = 12 * 3600

    struct Profile {
        /// Units (or percent) per hour for each hour of the day.
        var weekday: [Double]
        var weekend: [Double]
        var separated: Bool
        var daysCovered: Double
        /// Relative day-to-day spread of the daily consumption.
        var cv: Double

        func rate(hour: Int, weekend isWeekend: Bool) -> Double { (isWeekend ? weekend : weekday)[hour] }
    }

    private struct Bucket { var consumed = 0.0, covered = 0.0 }
    private struct Key: Hashable { var day: Int, hour: Int }

    // MARK: Profile

    func profile(kind: SupplyKind, samples: [SupplySample], now: Date) -> Profile? {
        let pts = samples.compactMap { s in s.value(for: kind).map { (s.date, $0) } }.sorted { $0.0 < $1.0 }
        guard pts.count >= 2 else { return nil }

        var buckets: [Key: Bucket] = [:]
        var dayStart: [Int: Date] = [:]
        var covered = 0.0
        // `ref` is the lowest level since the last change: small upward jitter (noise, rounding)
        // is ignored instead of counted twice; a large rise is a change and starts a new segment.
        var ref = pts[0].1
        for (a, b) in zip(pts, pts.dropFirst()) {
            let dt = b.0.timeIntervalSince(a.0)
            guard dt > 0 else { continue }
            guard dt <= maxGap else { ref = b.1; continue }            // gap: nothing to evaluate
            if b.1 > ref + kind.changeTolerance { ref = b.1; continue } // reservoir change / battery swap
            let rate = max(0, ref - b.1) / dt                          // never negative
            ref = min(ref, b.1)
            covered += dt
            var t = a.0
            while t < b.0 {
                let end = min(b.0, calendar.dateInterval(of: .hour, for: t)?.end ?? b.0)
                let piece = end.timeIntervalSince(t)
                guard piece > 0 else { break }
                let day = calendar.startOfDay(for: t)
                let key = Key(day: Int(day.timeIntervalSince1970), hour: calendar.component(.hour, from: t))
                buckets[key, default: Bucket()].consumed += rate * piece
                buckets[key, default: Bucket()].covered += piece
                dayStart[key.day] = day
                t = end
            }
        }
        buckets = buckets.filter { $0.value.covered >= 600 }
        guard !buckets.isEmpty else { return nil }

        // Winsorise per hour slot: spikes (glitches, one-off events) are capped.
        var capped: [Key: Double] = [:]   // consumption rate (per hour) after capping
        // Floor of the cap: coarse values (whole percent) would otherwise clip every step to 0.
        let medianRate = Self.median(buckets.values.map { $0.consumed / $0.covered * 3600 }.sorted())
        let capFloor = max(2 * medianRate, 2 * kind.resolution)
        for hour in 0..<24 {
            let slot = buckets.filter { $0.key.hour == hour }
            guard !slot.isEmpty else { continue }
            let rates = slot.values.map { $0.consumed / $0.covered * 3600 }.sorted()
            let cap: Double
            if rates.count >= 4 {
                let med = Self.median(rates)
                let mad = Self.median(rates.map { abs($0 - med) }.sorted()) * 1.4826
                cap = max(med + 5 * mad, 2.5 * med, capFloor)
            } else {
                cap = .infinity
            }
            for (k, b) in slot { capped[k] = min(b.consumed / b.covered * 3600, cap) }
        }

        func isWeekend(_ day: Int) -> Bool {
            let wd = calendar.component(.weekday, from: dayStart[day]!)
            return wd == 1 || wd == 7
        }
        func weight(_ k: Key) -> Double {
            let mid = dayStart[k.day]!.addingTimeInterval((Double(k.hour) + 0.5) * 3600)
            return pow(0.5, max(0, now.timeIntervalSince(mid)) / 86400 / halfLifeDays)
        }
        func rates(_ filter: (Key) -> Bool) -> [Double?] {
            (0..<24).map { h in
                var num = 0.0, den = 0.0
                for (k, r) in capped where k.hour == h && filter(k) {
                    let w = weight(k) * buckets[k]!.covered
                    num += w * r; den += w
                }
                return den > 0 ? num / den : nil
            }
        }

        // Days with at least 6 h of data count as "days with data" for the weekday/weekend split.
        var perDay: [Int: Double] = [:]
        for (k, b) in buckets { perDay[k.day, default: 0] += b.covered }
        let fullDays = perDay.filter { $0.value >= 6 * 3600 }.keys
        let weekendDays = fullDays.filter(isWeekend).count
        let weekdayDays = fullDays.count - weekendDays
        let separated = weekendDays >= 2 && weekdayDays >= 3

        let all = rates { _ in true }
        let allKnown = all.compactMap { $0 }
        guard !allKnown.isEmpty else { return nil }
        let mean = allKnown.reduce(0, +) / Double(allKnown.count)
        func filled(_ r: [Double?]) -> [Double] { (0..<24).map { r[$0] ?? all[$0] ?? mean } }

        let wd = separated ? filled(rates { !isWeekend($0.day) }) : filled(all)
        let we = separated ? filled(rates { isWeekend($0.day) }) : filled(all)
        let prof = Profile(weekday: wd, weekend: we, separated: separated, daysCovered: covered / 86400, cv: 0)

        // Spread of the daily totals (days with >= 20 h of data; missing hours use the profile).
        var totals: [(total: Double, weekend: Bool, w: Double)] = []
        for day in perDay.keys where perDay[day]! >= 20 * 3600 {
            var total = 0.0
            for h in 0..<24 { total += capped[Key(day: day, hour: h)] ?? prof.rate(hour: h, weekend: isWeekend(day)) }
            let w = pow(0.5, max(0, now.timeIntervalSince(dayStart[day]!)) / 86400 / halfLifeDays)
            totals.append((total, separated && isWeekend(day), w))
        }
        var cv = 0.3
        if totals.count >= 2 {
            var sq = 0.0, sw = 0.0, sum = 0.0
            for g in [false, true] {
                let grp = totals.filter { $0.weekend == g }
                let gw = grp.reduce(0) { $0 + $1.w }
                guard gw > 0, grp.count >= 2 else { continue }
                let m = grp.reduce(0) { $0 + $1.total * $1.w } / gw
                sq += grp.reduce(0) { $0 + $1.w * ($1.total - m) * ($1.total - m) }
                sw += gw; sum += m * gw
            }
            if sw > 0, sum > 0 { cv = max(0.03, (sq / sw).squareRoot() / (sum / sw)) }
        }
        var result = prof
        result.cv = cv
        return result
    }

    private static func median(_ sorted: [Double]) -> Double {
        let n = sorted.count
        return n % 2 == 1 ? sorted[n / 2] : (sorted[n / 2 - 1] + sorted[n / 2]) / 2
    }

    // MARK: Forecast

    func forecast(kind: SupplyKind, samples: [SupplySample], now: Date) -> SupplyOutcome {
        guard let last = samples.last(where: { $0.value(for: kind) != nil && $0.date <= now.addingTimeInterval(300) }),
              let level = last.value(for: kind),
              now.timeIntervalSince(last.date) <= maxStaleness else { return .noData }
        guard let prof = profile(kind: kind, samples: samples, now: now) else {
            return .learning(days: 0, needed: minDays)
        }
        guard prof.daysCovered >= minDays else { return .learning(days: prof.daysCovered, needed: minDays) }
        let mean = (prof.weekday + prof.weekend).reduce(0, +) / 48
        guard mean > 1e-9 else {
            return .ready(SupplyPrediction(current: level, basis: last.date, empty: nil, alarm: nil,
                                           confidence: 0, daysOfData: prof.daysCovered))
        }

        func estimate(_ threshold: Double) -> SupplyEstimate? {
            if level <= threshold { return SupplyEstimate(date: last.date, earliest: last.date, latest: last.date) }
            guard let mid = simulate(prof, from: last.date, level: level, threshold: threshold, scale: 1) else { return nil }
            let days = max(1, mid.timeIntervalSince(last.date) / 86400)
            let nEff = max(1, prof.daysCovered)
            let f = min(0.9, (prof.cv * prof.cv / days + prof.cv * prof.cv / nEff).squareRoot())
            let early = simulate(prof, from: last.date, level: level, threshold: threshold, scale: 1 + f) ?? mid
            let late = simulate(prof, from: last.date, level: level, threshold: threshold, scale: 1 - f) ?? mid.addingTimeInterval(horizonDays * 86400)
            return SupplyEstimate(date: mid, earliest: early, latest: late)
        }
        let confidence = min(1, prof.daysCovered / 7) * max(0, 1 - min(1, 2 * prof.cv))
        return .ready(SupplyPrediction(current: level, basis: last.date, empty: estimate(0),
                                       alarm: estimate(kind.alarmThreshold),
                                       confidence: confidence, daysOfData: prof.daysCovered))
    }

    /// Hour by hour until `level` falls to `threshold`; nil beyond the horizon.
    private func simulate(_ p: Profile, from start: Date, level: Double, threshold: Double, scale: Double) -> Date? {
        var t = start
        var left = level - threshold
        let limit = start.addingTimeInterval(horizonDays * 86400)
        while t < limit {
            let end = calendar.dateInterval(of: .hour, for: t)?.end ?? t.addingTimeInterval(3600)
            let hours = end.timeIntervalSince(t) / 3600
            let wd = calendar.component(.weekday, from: t)
            let r = p.rate(hour: calendar.component(.hour, from: t), weekend: wd == 1 || wd == 7) * scale * hours
            if r >= left, r > 0 { return t.addingTimeInterval(left / r * end.timeIntervalSince(t)) }
            left -= r
            t = end
        }
        return nil
    }
}
