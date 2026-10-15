// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation

/// Therapy event from the pump history, as shown in the chart and uploaded to Nightscout.
public struct Treatment: Codable, Equatable, Sendable, Identifiable {
    /// Kinds of treatments derived from the pump history.
    public enum Kind: String, Codable, Sendable {
        /// User-initiated bolus (manual or bolus wizard, usually with carbs).
        case bolus
        /// SmartGuard auto correction bolus.
        case autoCorrection
        case autoBasal, carbs, bgCheck, calibration, basalChange, suspend, resume

        public var isAutomatic: Bool { self == .autoBasal || self == .autoCorrection }
    }

    /// Pump history sequence number.
    public let id: UInt32
    public let date: Date
    public let kind: Kind
    /// Units (bolus, auto basal), grams (carbs), mg/dL (BG, calibration), U/h (basal).
    public let value: Double?

    /// Creates a treatment; `id` is the history sequence number (stable across re-reads).
    public init(id: UInt32, date: Date, kind: Kind, value: Double?) {
        self.id = id
        self.date = date
        self.kind = kind
        self.value = value
    }

    /// Builds treatments from a run of history events. A delivered bolus is classified with
    /// the activation type of its second part (next record): "commanded" (0x5A) means a
    /// SmartGuard auto correction.
    public static func from(_ events: [TimedHistoryEvent]) -> [Treatment] {
        let sorted = events.sorted { $0.sequence < $1.sequence }
        var details: [UInt32: UInt8?] = [:]
        for e in sorted { if case .bolusDeliveredDetails(let a) = e.event { details[e.sequence] = a } }
        return sorted.compactMap { e in
            guard var t = Treatment(e) else { return nil }
            if t.kind == .bolus, let activation = details[e.sequence + 1] ?? nil, activation == 0x5A {
                t = Treatment(id: t.id, date: t.date, kind: .autoCorrection, value: t.value)
            }
            return t
        }
    }

    /// Converts a history event into a treatment, or nil for events that are not treatments.
    public init?(_ e: TimedHistoryEvent) {
        switch e.event {
        case .bolusDelivered(_, let fast, let ext, _):
            guard fast + ext > 0 else { return nil }
            self.init(id: e.sequence, date: e.date, kind: .bolus, value: fast + ext)
        case .autoBasal(let units):
            guard units > 0 else { return nil }
            self.init(id: e.sequence, date: e.date, kind: .autoBasal, value: units)
        case .meal(let grams):
            guard grams > 0 else { return nil }
            self.init(id: e.sequence, date: e.date, kind: .carbs, value: grams)
        case .bgReading(let mgdl):
            self.init(id: e.sequence, date: e.date, kind: .bgCheck, value: mgdl)
        case .calibration(let mgdl, let accepted):
            guard accepted else { return nil }
            self.init(id: e.sequence, date: e.date, kind: .calibration, value: mgdl)
        case .basalRateChanged(_, let new):
            self.init(id: e.sequence, date: e.date, kind: .basalChange, value: new)
        case .deliveryStopped:
            self.init(id: e.sequence, date: e.date, kind: .suspend, value: nil)
        case .deliveryRestarted:
            self.init(id: e.sequence, date: e.date, kind: .resume, value: nil)
        default:
            return nil
        }
    }
}

extension Nightscout {
    /// Exact decimal for JSON (avoids 0.05000000000000003).
    static func dec(_ v: Double?, _ digits: Int = 3) -> NSDecimalNumber {
        NSDecimalNumber(string: String(format: "%.\(digits)f", v ?? 0))
    }

    /// Nightscout treatment (API v1). Auto basal micro boluses only if `includeAutoBasal`,
    /// basal rate changes are not uploaded (the pump status carries the current rate).
    public static func treatment(_ t: Treatment, includeAutoBasal: Bool = false) -> [String: Any]? {
        var out: [String: Any] = [
            "created_at": isoString(t.date),
            "enteredBy": device,
            "pumpId": Int(t.id),
        ]
        switch t.kind {
        case .bolus:
            out["eventType"] = "Correction Bolus"
            out["insulin"] = dec(t.value)
        case .autoCorrection:
            out["eventType"] = "Correction Bolus"
            out["insulin"] = dec(t.value)
            out["automatic"] = true
            out["notes"] = "SmartGuard Autokorrektur"
        case .autoBasal:
            guard includeAutoBasal else { return nil }
            out["eventType"] = "Correction Bolus"
            out["insulin"] = dec(t.value)
            out["automatic"] = true
            out["type"] = "SMB"
        case .carbs:
            out["eventType"] = "Carb Correction"
            out["carbs"] = dec(t.value, 0)
        case .bgCheck, .calibration:
            out["eventType"] = "BG Check"
            out["glucose"] = dec(t.value, 0)
            out["glucoseType"] = "Finger"
            out["units"] = "mg/dl"
            if t.kind == .calibration { out["notes"] = "Kalibrierung" }
        case .suspend:
            out["eventType"] = "Suspend Pump"
        case .resume:
            out["eventType"] = "Resume Pump"
        case .basalChange:
            return nil
        }
        return out
    }
}
