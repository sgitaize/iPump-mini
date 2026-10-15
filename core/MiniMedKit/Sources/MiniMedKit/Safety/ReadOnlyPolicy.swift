// SPDX-License-Identifier: GPL-3.0-or-later
// HARD RULE 1 (docs/internal/project-brief.md): read only.
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
        PumpUUID.gstBatteryLevel, PumpUUID.batteryLevel, PumpUUID.iddHistoryData,
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
        // operator Last (0x06). The 780G does not support ">= time offset" (lab notebook).
        // Delete (0x02) and everything else is blocked.
        case (PumpUUID.cgmService, PumpUUID.recordAccessCP):
            if p == [0x01, 0x06] { return .allowed("CGM RACP: letzter Datensatz") }
            return .blocked("CGM RACP: nicht erlaubter Befehl \(p.hex)")

        // IDD Record Access Control Point (pump history, IDS opcodes). Allowed are only
        // the reporting commands with filter type "sequence number" (0x0F), as used by
        // the official app (capture 2): Report Stored Records (0x33) with Last (0x69),
        // First (0x66) or Within Range (0x5A + two u32), and Report Number of Stored
        // Records (0x5A) for All (0x33). Delete Stored Records (0x3C) and Abort (0x55)
        // are blocked. Approved by Simon on 2026-10-15.
        case (PumpUUID.iddService.uppercased(), PumpUUID.recordAccessCP):
            if p == [0x33, 0x69, 0x0F] { return .allowed("IDD RACP: letzter History-Eintrag") }
            if p == [0x33, 0x66, 0x0F] { return .allowed("IDD RACP: erster History-Eintrag") }
            if p == [0x5A, 0x33, 0x0F] { return .allowed("IDD RACP: Anzahl History-Einträge") }
            if p.count == 11, p[0] == 0x33, p[1] == 0x5A, p[2] == 0x0F { return .allowed("IDD RACP: History-Bereich") }
            return .blocked("IDD RACP: nicht erlaubter Befehl \(p.hex)")

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
