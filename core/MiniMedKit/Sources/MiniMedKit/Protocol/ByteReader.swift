// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation

public enum ParseError: Error, Equatable {
    case tooShort
    case crcMismatch
    case unexpectedOpcode(UInt16)
    case lengthMismatch
    case trailingBytes(Int)
}

/// Little-endian reader for GATT payloads.
struct ByteReader {
    private let bytes: [UInt8]
    private(set) var offset = 0

    init(_ bytes: [UInt8]) { self.bytes = bytes }

    var remaining: Int { bytes.count - offset }

    mutating func u8() throws -> UInt8 {
        guard remaining >= 1 else { throw ParseError.tooShort }
        defer { offset += 1 }
        return bytes[offset]
    }

    mutating func i8() throws -> Int8 { Int8(bitPattern: try u8()) }

    mutating func u16() throws -> UInt16 {
        guard remaining >= 2 else { throw ParseError.tooShort }
        defer { offset += 2 }
        return UInt16(bytes[offset]) | UInt16(bytes[offset + 1]) << 8
    }

    mutating func u32() throws -> UInt32 {
        guard remaining >= 4 else { throw ParseError.tooShort }
        defer { offset += 4 }
        return (0..<4).reduce(UInt32(0)) { $0 | UInt32(bytes[offset + $1]) << (8 * UInt32($1)) }
    }

    /// IEEE-11073 16-bit SFLOAT (4-bit exponent, 12-bit mantissa).
    mutating func sfloat() throws -> Double { MedFloat.decode16(try u16()) }

    /// IEEE-11073 32-bit FLOAT (8-bit exponent, 24-bit mantissa).
    mutating func float32() throws -> Double { MedFloat.decode32(try u32()) }

    func expectEnd() throws {
        if remaining > 0 { throw ParseError.trailingBytes(remaining) }
    }
}

public enum MedFloat {
    public static func decode16(_ raw: UInt16) -> Double {
        var e = Int((raw >> 12) & 0x0F)
        var m = Int(raw & 0x0FFF)
        if e >= 0x8 { e -= 0x10 }
        if m >= 0x800 { m -= 0x1000 }
        return scaled(m, e)
    }

    public static func decode32(_ raw: UInt32) -> Double {
        var e = Int((raw >> 24) & 0xFF)
        var m = Int(raw & 0x00FF_FFFF)
        if e >= 0x80 { e -= 0x100 }
        if m >= 0x80_0000 { m -= 0x100_0000 }
        return scaled(m, e)
    }

    /// Avoids binary rounding noise such as 1.1600000000000001.
    private static func scaled(_ m: Int, _ e: Int) -> Double {
        Double("\(m)e\(e)") ?? Double(m) * pow(10, Double(e))
    }
}
