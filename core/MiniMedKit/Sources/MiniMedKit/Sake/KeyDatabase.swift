// SPDX-License-Identifier: GPL-3.0-or-later
// SAKE key database. Format and semantics from OpenMinimed (Documentation/key_databases.md).
// The database itself is NOT part of this repository; the app loads it from a local file.
import Foundation

public enum SakeDeviceType: UInt8, Sendable {
    case insulinPump = 1
    case glucoseSensor = 2
    case bloodGlucoseMeter = 3
    case mobileApplication = 4
    case careLinkUpload = 5
    case firmwareUpdate = 6
    case diagnostic = 7
    case primaryDisplay = 8
}

public struct StaticKeys: Sendable {
    public let derivationKey: [UInt8]
    public let handshakeAuthKey: [UInt8]
    public let permitDecryptKey: [UInt8]
    public let permitAuthKey: [UInt8]
    public let handshakePayload: [UInt8]
}

public enum KeyDatabaseError: Error, Equatable {
    case invalidHex
    case tooShort
    case crcMismatch
    case invalidLength
    case unknownDeviceType(UInt8)
}

public struct KeyDatabase: Sendable {
    public let localDeviceType: SakeDeviceType
    public let remoteDevices: [SakeDeviceType: StaticKeys]

    public init(bytes: [UInt8]) throws {
        guard bytes.count >= 6 else { throw KeyDatabaseError.tooShort }
        let crc = UInt32(bytes[0]) << 24 | UInt32(bytes[1]) << 16 | UInt32(bytes[2]) << 8 | UInt32(bytes[3])
        guard Checksums.crc32(Array(bytes[4...])) == crc else { throw KeyDatabaseError.crcMismatch }
        let n = Int(bytes[5])
        guard bytes.count == 6 + 81 * n else { throw KeyDatabaseError.invalidLength }
        guard let local = SakeDeviceType(rawValue: bytes[4]) else {
            throw KeyDatabaseError.unknownDeviceType(bytes[4])
        }
        var remotes: [SakeDeviceType: StaticKeys] = [:]
        for i in 0..<n {
            let p = 6 + 81 * i
            guard let type = SakeDeviceType(rawValue: bytes[p]) else {
                throw KeyDatabaseError.unknownDeviceType(bytes[p])
            }
            let k = { (j: Int) in Array(bytes[(p + 1 + 16 * j)..<(p + 17 + 16 * j)]) }
            remotes[type] = StaticKeys(derivationKey: k(0), handshakeAuthKey: k(1),
                                       permitDecryptKey: k(2), permitAuthKey: k(3),
                                       handshakePayload: k(4))
        }
        localDeviceType = local
        remoteDevices = remotes
    }

    public init(hex: String) throws {
        guard let bytes = [UInt8](hex: hex) else { throw KeyDatabaseError.invalidHex }
        try self.init(bytes: bytes)
    }
}

extension Array where Element == UInt8 {
    /// Parses hex, ignoring whitespace. Returns nil on invalid input.
    public init?(hex: String) {
        let clean = hex.filter { !$0.isWhitespace }
        guard clean.count % 2 == 0 else { return nil }
        var out = [UInt8]()
        out.reserveCapacity(clean.count / 2)
        var index = clean.startIndex
        while index < clean.endIndex {
            let next = clean.index(index, offsetBy: 2)
            guard let b = UInt8(clean[index..<next], radix: 16) else { return nil }
            out.append(b)
            index = next
        }
        self = out
    }

    public var hex: String { map { String(format: "%02x", $0) }.joined() }
}

extension KeyDatabase {
    /// Finds a database in a text: plain hex, or a page with several hex blocks such as
    /// OpenMinimed's key_databases.md (blocks in <code>…</code>, hex groups separated by
    /// spaces). Returns the hex of the first block that parses and passes `accept`.
    public static func findHex(in text: String, accept: (KeyDatabase) -> Bool) -> String? {
        var candidates: [String] = []
        var rest = text[...]
        while let open = rest.range(of: "<code>"),
              let close = rest.range(of: "</code>", range: open.upperBound..<rest.endIndex) {
            candidates.append(String(rest[open.upperBound..<close.lowerBound]))
            rest = rest[close.upperBound...]
        }
        candidates.append(text)
        for candidate in candidates {
            let clean = candidate.filter { !$0.isWhitespace }
            guard !clean.isEmpty, clean.allSatisfy(\.isHexDigit),
                  let db = try? KeyDatabase(hex: clean), accept(db) else { continue }
            return clean
        }
        return nil
    }
}
