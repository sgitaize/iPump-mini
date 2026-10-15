// SPDX-License-Identifier: GPL-3.0-or-later
// CGM service payloads (Bluetooth CGMS + Medtronic usage, see OpenMinimed cgm-service.md).
import Foundation

/// CGM Measurement record (GSS 3.43). The 780G always appends an E2E-CRC.
public struct CGMMeasurement: Equatable, Sendable, Codable {
    public let glucoseMgdl: Double
    /// Minutes since the start of the sensor session.
    public let timeOffsetMinutes: UInt16
    public let status: UInt8
    public let calTemp: UInt8
    public let warning: UInt8
    /// Rate of change in mg/dL/min.
    public let trendMgdlPerMin: Double?
    /// Quality as raw value; meaning on the 780G not yet verified.
    public let quality: Double?

    /// Parses a measurement record; throws on short data or a wrong E2E-CRC.
    public init(_ data: [UInt8], hasE2ECRC: Bool = true) throws {
        guard data.count >= (hasE2ECRC ? 8 : 6) else { throw ParseError.tooShort }
        if hasE2ECRC, !Checksums.hasValidE2ECRC(data) { throw ParseError.crcMismatch }
        guard Int(data[0]) == data.count else { throw ParseError.lengthMismatch }
        var r = ByteReader(hasE2ECRC ? Array(data.dropLast(2)) : data)
        _ = try r.u8() // size
        let flags = try r.u8()
        glucoseMgdl = try r.sfloat()
        timeOffsetMinutes = try r.u16()
        status = flags & 0x80 != 0 ? try r.u8() : 0
        calTemp = flags & 0x40 != 0 ? try r.u8() : 0
        warning = flags & 0x20 != 0 ? try r.u8() : 0
        trendMgdlPerMin = flags & 0x01 != 0 ? try r.sfloat() : nil
        quality = flags & 0x02 != 0 ? try r.sfloat() : nil
        try r.expectEnd()
    }
}

/// CGM Session Start Time (GSS): date-time (7) + time zone (i8, 15 min) + DST (u8, 15 min) + E2E-CRC.
public struct CGMSessionStartTime: Equatable, Sendable {
    public let components: DateComponents
    public let timeZoneOffsetMinutes: Int?
    public let dstOffsetMinutes: Int?

    /// Parses the session start time; throws on short data or a wrong E2E-CRC.
    public init(_ data: [UInt8]) throws {
        guard data.count == 11 else { throw ParseError.lengthMismatch }
        guard Checksums.hasValidE2ECRC(data) else { throw ParseError.crcMismatch }
        var r = ByteReader(data)
        var c = DateComponents()
        c.year = Int(try r.u16())
        c.month = Int(try r.u8())
        c.day = Int(try r.u8())
        c.hour = Int(try r.u8())
        c.minute = Int(try r.u8())
        c.second = Int(try r.u8())
        components = c
        let tz = try r.i8()
        let dst = try r.u8()
        timeZoneOffsetMinutes = tz == -128 ? nil : Int(tz) * 15
        dstOffsetMinutes = dst == 0xFF ? nil : Int(dst) * 15
    }

    /// Absolute start time. If the pump does not send a time zone, its clock is
    /// interpreted in `fallbackTimeZone` (the phone's zone; the pump clock is local time).
    public func date(fallbackTimeZone: TimeZone = .current) -> Date? {
        var c = components
        if let tz = timeZoneOffsetMinutes {
            c.timeZone = TimeZone(secondsFromGMT: (tz + (dstOffsetMinutes ?? 0)) * 60)
        } else {
            c.timeZone = fallbackTimeZone
        }
        return Calendar(identifier: .gregorian).date(from: c)
    }
}
