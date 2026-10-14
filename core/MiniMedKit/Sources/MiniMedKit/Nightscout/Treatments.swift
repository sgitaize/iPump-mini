// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation

/// Therapy event from the pump history, as shown in the chart and uploaded to Nightscout.
public struct Treatment: Codable, Equatable, Sendable, Identifiable {
    public enum Kind: String, Codable, Sendable {
        case bolus, autoBasal, carbs, bgCheck, calibration, basalChange, suspend, resume
    }

    /// Pump history sequence number.
    public let id: UInt32
    public let date: Date
    public let kind: Kind
    /// Units (bolus, auto basal), grams (carbs), mg/dL (BG, calibration), U/h (basal).
    public let value: Double?

    public init(id: UInt32, date: Date, kind: Kind, value: Double?) {
        self.id = id
        self.date = date
        self.kind = kind
        self.value = value
    }

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
