// SPDX-License-Identifier: GPL-3.0-or-later
// Insulin Delivery Service payloads as used by the 780G (OpenMinimed idd-service.md).
// All of them arrive SAKE-encrypted and are decrypted before parsing.
import Foundation

/// Read-only Status Reader opcodes we are allowed to send. Everything else is blocked
/// by `ReadOnlyPolicy`.
public enum StatusReaderOpcode: UInt16, CaseIterable, Sendable {
    case getActiveBasalRateDelivery = 0x0365
    case getInsulinOnBoard = 0x03F3
    case getTherapyAlgorithmStates = 0x03FD
    case getTimeInRange = 0x0401

    public var responseOpcode: UInt16 {
        switch self {
        case .getActiveBasalRateDelivery: 0x036A
        case .getInsulinOnBoard: 0x03FC
        case .getTherapyAlgorithmStates: 0x03FE
        case .getTimeInRange: 0x0402
        }
    }

    public var request: [UInt8] { [UInt8(rawValue & 0xFF), UInt8(rawValue >> 8)] }
}

/// Opcode of a decrypted Status Reader indication (first two bytes, little-endian).
public func statusReaderResponseOpcode(_ data: [UInt8]) -> UInt16? {
    guard data.count >= 2 else { return nil }
    return UInt16(data[0]) | UInt16(data[1]) << 8
}

/// IDD Status characteristic.
public struct PumpStatus: Equatable, Sendable, Codable {
    /// IDS therapy control state (run, pause, stop).
    public enum TherapyControlState: UInt8, Codable, Sendable { case undetermined = 0x0F, stop = 0x33, pause = 0x3C, run = 0x55 }
    /// IDS operational state of the pump.
    public enum OperationalState: UInt8, Codable, Sendable {
        case undetermined = 0x0F, off = 0x33, standby = 0x3C, preparing = 0x55, priming = 0x5A, waiting = 0x66, ready = 0x96
    }

    public let therapyControlState: TherapyControlState?
    public let operationalState: OperationalState?
    public let reservoirUnits: Double
    public let reservoirAttached: Bool
    public let sensorConnectivity: UInt8
    public let sensorMessageState: UInt8

    /// Parses the decrypted payload; throws if it is too short or malformed.
    public init(_ data: [UInt8]) throws {
        guard data.count == 9 else { throw ParseError.lengthMismatch }
        var r = ByteReader(data)
        therapyControlState = TherapyControlState(rawValue: try r.u8())
        operationalState = OperationalState(rawValue: try r.u8())
        reservoirUnits = try r.float32()
        reservoirAttached = (try r.u8()) & 0x01 != 0
        sensorConnectivity = try r.u8()
        sensorMessageState = try r.u8()
    }

    public var isSuspended: Bool { therapyControlState == .pause || therapyControlState == .stop }
    public var sensorOn: Bool { sensorConnectivity & 0x01 != 0 }
    public var sensorSignalLost: Bool { sensorConnectivity & 0x04 != 0 }
    /// No sensor message pending and a signal is there.
    public var sensorOK: Bool {
        (sensorMessageState == 0x00 || sensorMessageState == 0x0C) && sensorOn && !sensorSignalLost
    }

    public var sensorMessage: String {
        switch sensorMessageState {
        case 0x00: "Sensor ok"
        case 0x01: "Warten auf Kalibrierung"
        case 0x02: "Nicht kalibrieren"
        case 0x03: "Kalibrierung erforderlich"
        case 0x04: "Kalibriert"
        case 0x05: "Sensorsignal wird gesucht"
        case 0x06: "Kein Sensorsignal"
        case 0x07: "Sensor wechseln"
        case 0x08: "Aufwärmphase"
        case 0x09: "SG unter Messbereich"
        case 0x0A: "SG über Messbereich"
        case 0x0B: "Transmitter-Batterie leer"
        case 0x0C: "Sensor verbunden"
        case 0x0D: "Warten auf Aufwärmphase"
        case 0x0E: "Kein Sensor gekoppelt"
        default: String(format: "Unbekannt (0x%02x)", sensorMessageState)
        }
    }
}

/// Active insulin (IOB) as reported by the pump's status reader.
public struct InsulinOnBoard: Equatable, Sendable, Codable {
    public let units: Double
    public let remainingDurationMinutes: UInt16?

    /// Parses the decrypted payload; throws if it is too short or malformed.
    public init(_ data: [UInt8]) throws {
        var r = ByteReader(data)
        let opcode = try r.u16()
        guard opcode == StatusReaderOpcode.getInsulinOnBoard.responseOpcode else { throw ParseError.unexpectedOpcode(opcode) }
        let flags = try r.u8()
        units = try r.float32()
        remainingDurationMinutes = flags & 0x01 != 0 ? try r.u16() : nil
        if flags & 0x02 != 0 { _ = try r.u16(); _ = try r.u16() }
        try r.expectEnd()
    }
}

/// Time in range statistics from the pump (percent of today).
public struct TimeInRange: Equatable, Sendable, Codable {
    public let notEnoughData: Bool
    public let abovePercent: UInt8
    public let belowPercent: UInt8
    public let inRangePercent: UInt8
    public let smartGuardPercent: UInt8

    /// Parses the decrypted payload; throws if it is too short or malformed.
    public init(_ data: [UInt8]) throws {
        guard data.count == 7 else { throw ParseError.lengthMismatch }
        var r = ByteReader(data)
        let opcode = try r.u16()
        guard opcode == StatusReaderOpcode.getTimeInRange.responseOpcode else { throw ParseError.unexpectedOpcode(opcode) }
        notEnoughData = try r.u8() != 0
        abovePercent = try r.u8()
        belowPercent = try r.u8()
        inRangePercent = try r.u8()
        smartGuardPercent = try r.u8()
    }
}

/// SmartGuard algorithm state (Medtronic status reader opcode).
public struct TherapyAlgorithmStates: Equatable, Sendable, Codable {
    /// Mode of the closed loop: manual (open loop), SmartGuard auto basal or safe basal.
    public enum ShieldState: UInt8, Codable, Sendable { case openLoop = 1, autoBasal = 2, safeBasal = 3 }

    public let shieldState: ShieldState?
    public let readinessState: UInt8?
    public let tempTargetMinutes: UInt16?
    public let safeBasalMinutes: UInt16?

    /// Parses the decrypted payload; throws if it is too short or malformed.
    public init(_ data: [UInt8]) throws {
        var r = ByteReader(data)
        let opcode = try r.u16()
        guard opcode == StatusReaderOpcode.getTherapyAlgorithmStates.responseOpcode else { throw ParseError.unexpectedOpcode(opcode) }
        let flags = try r.u16()
        if flags & 0x01 != 0 {
            shieldState = ShieldState(rawValue: try r.u8())
            readinessState = try r.u8()
        } else {
            shieldState = nil
            readinessState = nil
        }
        if flags & 0x04 != 0 { _ = try r.u8() } // PLGM state
        if flags & 0x02 != 0 { _ = try r.u8() } // LGS state
        tempTargetMinutes = flags & 0x08 != 0 ? try r.u16() : nil
        if flags & 0x10 != 0 { _ = try r.u16() } // wait to calibrate
        safeBasalMinutes = flags & 0x20 != 0 ? try r.u16() : nil
        try r.expectEnd()
    }

    public var modeDescription: String {
        switch shieldState {
        case .autoBasal: "SmartGuard"
        case .safeBasal: "Sicherheitsbasal"
        case .openLoop: "Manueller Modus"
        case nil: "–"
        }
    }
}

/// Active basal rate and a running temporary basal, if any.
public struct ActiveBasalRate: Equatable, Sendable, Codable {
    public let profileNumber: UInt8
    public let unitsPerHour: Double
    public let tempBasalUnitsPerHour: Double?
    public let tempBasalRemainingMinutes: UInt16?

    /// Parses the decrypted payload; throws if it is too short or malformed.
    public init(_ data: [UInt8]) throws {
        var r = ByteReader(data)
        let opcode = try r.u16()
        guard opcode == StatusReaderOpcode.getActiveBasalRateDelivery.responseOpcode else { throw ParseError.unexpectedOpcode(opcode) }
        let flags = try r.u8()
        profileNumber = try r.u8()
        unitsPerHour = try r.float32()
        if flags & 0x01 != 0 {
            _ = try r.u8() // TBR type
            tempBasalUnitsPerHour = try r.float32()
            _ = try r.u16() // programmed duration
            tempBasalRemainingMinutes = try r.u16()
        } else {
            tempBasalUnitsPerHour = nil
            tempBasalRemainingMinutes = nil
        }
        if flags & 0x02 != 0 { _ = try r.u8() }
        if flags & 0x04 != 0 { _ = try r.u8() }
        try r.expectEnd()
    }
}

/// IDD Status Changed (decrypted): flags. Bit 3 = annunciation status changed (IDS).
public struct StatusChangedFlags: OptionSet, Sendable {
    public let rawValue: UInt16
    /// Creates flags from the raw 16-bit value.
    public init(rawValue: UInt16) { self.rawValue = rawValue }
    /// Reads the flags from a decrypted Status Changed payload; nil if too short.
    public init?(_ data: [UInt8]) {
        guard data.count >= 2 else { return nil }
        rawValue = UInt16(data[0]) | UInt16(data[1]) << 8
    }
    public static let therapyControlState = StatusChangedFlags(rawValue: 1 << 0)
    public static let operationalState = StatusChangedFlags(rawValue: 1 << 1)
    public static let reservoir = StatusChangedFlags(rawValue: 1 << 2)
    public static let annunciation = StatusChangedFlags(rawValue: 1 << 3)
    public static let totalDailyInsulin = StatusChangedFlags(rawValue: 1 << 4)
    public static let activeBasal = StatusChangedFlags(rawValue: 1 << 5)
    public static let activeBolus = StatusChangedFlags(rawValue: 1 << 6)
    public static let history = StatusChangedFlags(rawValue: 1 << 7)
}
