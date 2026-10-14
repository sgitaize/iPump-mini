// SPDX-License-Identifier: GPL-3.0-or-later
// HARD RULE 1 (docs/project-brief.md): read only.
//
// Every GATT write towards the pump has to pass this policy. It is an allowlist:
// anything that is not listed here explicitly is blocked. Writes are checked on the
// plaintext, i.e. before SAKE encryption. Characteristic reads and enabling
// notifications/indications do not change the pump state and are handled separately.
//
// Changing this file needs Simon's review. If in doubt whether a message writes, it is
// forbidden.
import Foundation

public struct WriteRequest: Sendable, Equatable {
    public let service: String
    public let characteristic: String
    public let plaintext: [UInt8]

    public init(service: String, characteristic: String, plaintext: [UInt8]) {
        self.service = service.uppercased()
        self.characteristic = characteristic.uppercased()
        self.plaintext = plaintext
    }
}

public enum PolicyDecision: Equatable, Sendable {
    case allowed(String)
    case blocked(String)

    public var isAllowed: Bool { if case .allowed = self { true } else { false } }
}

public enum ReadOnlyPolicy {
    /// Characteristics we may subscribe to (CCCD write). Subscribing only asks the
    /// pump to report values and does not change therapy or settings.
    public static let subscribable: Set<String> = Set([
        PumpUUID.cgmMeasurement, PumpUUID.recordAccessCP,
        PumpUUID.iddStatusReaderCP, PumpUUID.iddStatusChanged,
    ].map { $0.uppercased() })

    /// Characteristics we may read.
    public static let readable: Set<String> = Set([
        PumpUUID.iddStatus, PumpUUID.iddStatusChanged, PumpUUID.cgmSessionStartTime,
        PumpUUID.cgmSessionRunTime, PumpUUID.cgmFeature, PumpUUID.serialNumber,
        PumpUUID.firmwareRevision, PumpUUID.modelNumber, PumpUUID.batteryLevel,
        PumpUUID.gstBatteryLevel, PumpUUID.sensorExpiration,
    ].map { $0.uppercased() })

    public static func check(_ request: WriteRequest) -> PolicyDecision {
        let p = request.plaintext
        switch (request.service, request.characteristic) {

        // CGM Record Access Control Point: only "Report Stored Records" (0x01) with
        // operator All (0x01), >= (0x03, filter time offset 0x01 + u16) or Last (0x06).
        // Delete (0x02) and everything else is blocked.
        case (PumpUUID.cgmService, PumpUUID.recordAccessCP):
            if p == [0x01, 0x06] { return .allowed("CGM RACP: letzter Datensatz") }
            if p == [0x01, 0x01] { return .allowed("CGM RACP: alle Datensätze") }
            if p.count == 5, p[0] == 0x01, p[1] == 0x03, p[2] == 0x01 {
                return .allowed("CGM RACP: Datensätze ab Zeit-Offset")
            }
            return .blocked("CGM RACP: nicht erlaubter Befehl \(p.hex)")

        // IDD Status Reader Control Point: only the read-only "Get …" opcodes of
        // StatusReaderOpcode, without parameters. Reset Status (0x030C) is blocked.
        case (PumpUUID.iddService.uppercased(), PumpUUID.iddStatusReaderCP.uppercased()):
            guard p.count == 2 else { return .blocked("IDD SRCP: unerwartete Länge \(p.count)") }
            let opcode = UInt16(p[0]) | UInt16(p[1]) << 8
            if let op = StatusReaderOpcode(rawValue: opcode) {
                return .allowed("IDD SRCP: \(op)")
            }
            return .blocked(String(format: "IDD SRCP: Opcode 0x%04x nicht erlaubt", opcode))

        default:
            // Includes IDD Command Control Point (bolus, basal, suspend, settings, …),
            // CGM Specific Ops (calibration, session start/stop), session start time
            // writes, IDD RACP (delete), History & Trace, NOS, SSE, certificate and
            // firmware services, Current Time.
            return .blocked("Schreiben auf \(request.characteristic) ist nicht freigegeben")
        }
    }

    public static func mayRead(_ characteristic: String) -> Bool {
        readable.contains(characteristic.uppercased())
    }

    public static func maySubscribe(_ characteristic: String) -> Bool {
        subscribable.contains(characteristic.uppercased())
    }
}

/// HARD RULE 2: in DEV_MODE only the test pump is accepted.
public struct DevModeGuard: Sendable {
    public let devMode: Bool
    public let testPumpSerial: String

    public init(devMode: Bool, testPumpSerial: String) {
        self.devMode = devMode
        self.testPumpSerial = testPumpSerial
    }

    /// The pump reports e.g. "NG1234567X" in DIS or "Pump 1234567X" as device name.
    /// We compare the 7 digits + check letter.
    public static func normalize(_ serial: String) -> String {
        var s = serial.uppercased().trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("PUMP ") { s.removeFirst(5) }
        if s.hasPrefix("NG") { s.removeFirst(2) }
        return s.filter { $0.isLetter || $0.isNumber }
    }

    public func accepts(serial: String?) -> Bool {
        guard devMode else { return true }
        guard let serial, !testPumpSerial.isEmpty else { return false }
        return Self.normalize(serial) == Self.normalize(testPumpSerial)
    }
}
