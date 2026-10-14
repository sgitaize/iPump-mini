// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation

public enum Checksums {
    /// CRC-32 (IEEE 802.3, zlib), used for the SAKE key database header.
    public static func crc32(_ data: [UInt8]) -> UInt32 {
        var crc: UInt32 = 0xFFFF_FFFF
        for byte in data {
            crc ^= UInt32(byte)
            for _ in 0..<8 {
                crc = (crc & 1) != 0 ? (crc >> 1) ^ 0xEDB8_8320 : crc >> 1
            }
        }
        return ~crc
    }

    /// E2E-CRC of the Bluetooth medical profiles: CRC-16/CCITT-FALSE
    /// (poly 0x1021, init 0xFFFF, no reflection, no final xor).
    public static func e2eCRC(_ data: [UInt8]) -> UInt16 {
        var crc: UInt16 = 0xFFFF
        for byte in data {
            crc ^= UInt16(byte) << 8
            for _ in 0..<8 {
                crc = (crc & 0x8000) != 0 ? (crc << 1) ^ 0x1021 : crc << 1
            }
        }
        return crc
    }

    /// Checks a payload whose last two bytes are a little-endian E2E-CRC.
    public static func hasValidE2ECRC(_ message: [UInt8]) -> Bool {
        guard message.count >= 2 else { return false }
        let body = Array(message.dropLast(2))
        let received = UInt16(message[message.count - 2]) | UInt16(message[message.count - 1]) << 8
        return e2eCRC(body) == received
    }
}
