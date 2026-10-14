// SPDX-License-Identifier: GPL-3.0-or-later
import XCTest
@testable import MiniMedKit

final class ReadOnlyPolicyTests: XCTestCase {
    private func check(_ service: String, _ char: String, _ hex: String) -> PolicyDecision {
        ReadOnlyPolicy.check(WriteRequest(service: service, characteristic: char, plaintext: [UInt8](hex: hex)!))
    }

    func testAllowsOnlyReadingCommands() {
        XCTAssertTrue(check(PumpUUID.cgmService, PumpUUID.recordAccessCP, "0106").isAllowed)
        XCTAssertTrue(check(PumpUUID.cgmService, PumpUUID.recordAccessCP, "0103011000").isAllowed)
        for op in StatusReaderOpcode.allCases {
            XCTAssertTrue(check(PumpUUID.iddService, PumpUUID.iddStatusReaderCP, op.request.hex).isAllowed, "\(op)")
        }
    }

    func testBlocksEverythingElse() {
        // CGM RACP delete / abort
        XCTAssertFalse(check(PumpUUID.cgmService, PumpUUID.recordAccessCP, "0201").isAllowed)
        XCTAssertFalse(check(PumpUUID.cgmService, PumpUUID.recordAccessCP, "0300").isAllowed)
        // IDD Status Reader: Reset Status, unknown opcodes, parameters appended
        XCTAssertFalse(check(PumpUUID.iddService, PumpUUID.iddStatusReaderCP, "0c03").isAllowed)
        XCTAssertFalse(check(PumpUUID.iddService, PumpUUID.iddStatusReaderCP, "f30300").isAllowed)
        XCTAssertFalse(check(PumpUUID.iddService, PumpUUID.iddStatusReaderCP, "3003").isAllowed)
        // Command CP (bolus, basal, suspend, settings) – always blocked, even with a "read" opcode
        XCTAssertFalse(check(PumpUUID.iddService, PumpUUID.iddCommandCP, "8e14").isAllowed)
        // IDD RACP incl. delete
        XCTAssertFalse(check(PumpUUID.iddService, PumpUUID.recordAccessCP, "3c33").isAllowed)
        // CGM specific ops (calibration, session start/stop), session start time write
        XCTAssertFalse(check(PumpUUID.cgmService, PumpUUID.cgmSpecificOpsCP, "1a").isAllowed)
        XCTAssertFalse(check(PumpUUID.cgmService, PumpUUID.cgmSessionStartTime, "00").isAllowed)
        // Same characteristic in a different service must not inherit permissions
        XCTAssertFalse(check("00000300-0000-1000-0000-009132591325", PumpUUID.recordAccessCP, "0106").isAllowed)
        XCTAssertFalse(check("1805", "2A2B", "00").isAllowed)
    }

    func testReadAndSubscribeLists() {
        XCTAssertTrue(ReadOnlyPolicy.mayRead(PumpUUID.iddStatus.lowercased()))
        XCTAssertFalse(ReadOnlyPolicy.mayRead(PumpUUID.iddCommandData))
        XCTAssertTrue(ReadOnlyPolicy.maySubscribe(PumpUUID.cgmMeasurement))
        XCTAssertFalse(ReadOnlyPolicy.maySubscribe(PumpUUID.iddCommandCP))
    }

    func testDevModeGuard() {
        let guardOn = DevModeGuard(devMode: true, testPumpSerial: "NG1234567H")
        XCTAssertTrue(guardOn.accepts(serial: "NG1234567H"))
        XCTAssertTrue(guardOn.accepts(serial: "Pump 1234567H"))
        XCTAssertTrue(guardOn.accepts(serial: "1234567h"))
        XCTAssertFalse(guardOn.accepts(serial: "NG7654321H"))
        XCTAssertFalse(guardOn.accepts(serial: nil))
        XCTAssertFalse(DevModeGuard(devMode: true, testPumpSerial: "").accepts(serial: "NG1234567H"))
        XCTAssertTrue(DevModeGuard(devMode: false, testPumpSerial: "").accepts(serial: "NG7654321H"))
    }
}
