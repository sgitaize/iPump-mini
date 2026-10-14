// SPDX-License-Identifier: GPL-3.0-or-later
// IDD History Data records (IDS + Medtronic events), read via the IDD RACP.
// Record layout and event formats from OpenMinimed (PythonPumpConnector history/data.py,
// Documentation/idd-service.md). Records arrive SAKE-encrypted and are decrypted first.
import Foundation

public enum HistoryEvent: Equatable, Sendable {
    /// Pump clock reference (local time, no time zone). Later records count their
    /// relative offset (seconds) from the latest reference.
    case referenceTime(DateComponents)
    case bolusDelivered(id: UInt16, fastUnits: Double, extendedUnits: Double, durationMinutes: UInt16)
    /// Second part of a delivered bolus (follows part 1). Activation type (IDS): 0x33 manual,
    /// 0x3C recommended (bolus wizard), 0x55 recommendation changed by the user,
    /// 0x5A commanded (SmartGuard auto correction).
    case bolusDeliveredDetails(activationType: UInt8?)
    /// SmartGuard auto basal (micro bolus).
    case autoBasal(units: Double)
    case meal(grams: Double)
    case bgReading(mgdl: Double)
    case calibration(mgdl: Double, accepted: Bool)
    case basalRateChanged(oldUnitsPerHour: Double, newUnitsPerHour: Double)
    case deliveryStopped(reason: UInt8)
    case deliveryRestarted(reason: UInt8)
    /// Sensor value from the pump history; nil for special states (warm-up, out of range…).
    case sensorGlucose(mgdl: Int?)
    /// Pump alert/alarm (Annunciation Consolidated). Status: 0x33 pending, 0x3C snoozed,
    /// 0x55 confirmed. Type without the 0xF000 marker.
    case annunciation(id: UInt16, type: UInt16, status: UInt8)
    case other(type: UInt16)
}

public struct HistoryRecord: Equatable, Sendable {
    public let eventType: UInt16
    public let sequence: UInt32
    /// Seconds since the latest reference time event.
    public let relativeOffset: UInt16
    public let event: HistoryEvent

    public init(_ data: [UInt8]) throws {
        var r = ByteReader(data)
        eventType = try r.u16()
        sequence = try r.u32()
        relativeOffset = try r.u16()
        event = try Self.parseEvent(type: eventType, &r)
    }

    /// kg/L as used by the pump for BG values → mg/dL.
    static func mgdl(fromKgPerL value: Double) -> Double { (value * 100_000).rounded() }

    private static func parseEvent(type: UInt16, _ r: inout ByteReader) throws -> HistoryEvent {
        switch type {
        case 0xF00E: // NGP reference time: recording reason + date-time
            _ = try r.u8()
            var c = DateComponents()
            c.year = Int(try r.u16())
            c.month = Int(try r.u8())
            c.day = Int(try r.u8())
            c.hour = Int(try r.u8())
            c.minute = Int(try r.u8())
            c.second = Int(try r.u8())
            try r.expectEnd()
            return .referenceTime(c)
        case 0x0069: // Bolus Delivered P1
            let id = try r.u16()
            _ = try r.u8() // bolus type
            let fast = try r.float32()
            let ext = try r.float32()
            let duration = try r.u16()
            try r.expectEnd()
            return .bolusDelivered(id: id, fastUnits: fast, extendedUnits: ext, durationMinutes: duration)
        case 0x0096: // Bolus Delivered P2: flags, start time offset, [activation], [end reason], [annunciation]
            let flags = try r.u8()
            _ = try r.u32()
            let activation: UInt8? = flags & 0x01 != 0 ? try r.u8() : nil
            if flags & 0x02 != 0 { _ = try r.u8() }
            if flags & 0x04 != 0 { _ = try r.u16() }
            try r.expectEnd()
            return .bolusDeliveredDetails(activationType: activation)
        case 0xF001: // Auto basal delivery
            _ = try r.u8()
            let units = try r.float32()
            try r.expectEnd()
            return .autoBasal(units: units)
        case 0xF005: // Meal
            let grams = try r.sfloat()
            try r.expectEnd()
            return .meal(grams: grams)
        case 0xF007: // BG reading
            _ = try r.u16() // time offset
            let bg = try r.sfloat()
            try r.expectEnd()
            return .bgReading(mgdl: mgdl(fromKgPerL: bg))
        case 0xF008, 0xF009: // Calibration complete / rejected
            _ = try r.u16()
            let bg = try r.sfloat()
            try r.expectEnd()
            return .calibration(mgdl: mgdl(fromKgPerL: bg), accepted: type == 0xF008)
        case 0x0099: // Delivered basal rate changed
            let flags = try r.u8()
            let old = try r.float32()
            let new = try r.float32()
            if flags & 0x01 != 0 { _ = try r.u8() }
            try r.expectEnd()
            return .basalRateChanged(oldUnitsPerHour: old, newUnitsPerHour: new)
        case 0xF00A:
            let reason = try r.u8()
            try r.expectEnd()
            return .deliveryStopped(reason: reason)
        case 0xF00B:
            let reason = try r.u8()
            try r.expectEnd()
            return .deliveryRestarted(reason: reason)
        case 0xF00C: // SG measurement: time offset, SG, ISIG, V counter
            _ = try r.u16()
            let sg = try r.u16()
            _ = try r.u16()
            _ = try r.u16()
            try r.expectEnd()
            // Values from 0x0300 on encode sensor states, not glucose.
            return .sensorGlucose(mgdl: sg < 0x0300 && sg >= 40 && sg <= 400 ? Int(sg) : nil)
        case 0xF010: // Annunciation Consolidated: flags, id, type (0xF…), status, timestamp, aux…
            _ = try r.u8()
            let id = try r.u16()
            let annType = try r.u16()
            let status = try r.u8()
            // The auxiliary data that follows depends on the type; it is not needed here.
            return .annunciation(id: id, type: annType & 0x0FFF, status: status)
        default:
            return .other(type: type)
        }
    }
}

/// A history event with its absolute time.
public struct TimedHistoryEvent: Equatable, Sendable {
    public let sequence: UInt32
    public let date: Date
    public let event: HistoryEvent
}

public enum HistoryTimeline {
    /// Resolves absolute times. `reference` is the latest reference time known before the
    /// first record (sequence + pump clock). Records before any reference are dropped.
    public static func resolve(_ records: [HistoryRecord], reference: (sequence: UInt32, date: Date)?,
                               timeZone: TimeZone = .current) -> (events: [TimedHistoryEvent], reference: (sequence: UInt32, date: Date)?) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        var ref = reference
        var out: [TimedHistoryEvent] = []
        for record in records.sorted(by: { $0.sequence < $1.sequence }) {
            if case .referenceTime(let c) = record.event, let d = calendar.date(from: c) {
                ref = (record.sequence, d)
                continue
            }
            guard let ref, record.sequence > ref.sequence else { continue }
            out.append(TimedHistoryEvent(sequence: record.sequence,
                                         date: ref.date.addingTimeInterval(Double(record.relativeOffset)),
                                         event: record.event))
        }
        return (out, ref)
    }
}
