// SPDX-License-Identifier: GPL-3.0-or-later
// Same cases as core/MiniMedKit/Tests/MiniMedKitTests/ReadOnlyPolicyTests.swift.
package de.sgitaize.minimedkit

import org.junit.Test
import kotlin.test.assertFalse
import kotlin.test.assertTrue

class ReadOnlyPolicyTest {
    private fun allowed(service: String, char: String, hexValue: String): Boolean =
        ReadOnlyPolicy.check(WriteRequest(service, char, hex(hexValue))).isAllowed

    @Test
    fun allowsOnlyReadingCommands() {
        assertTrue(allowed(PumpUuid.CGM_SERVICE, PumpUuid.RECORD_ACCESS_CP, "0106"))
        assertTrue(allowed(PumpUuid.IDD_SERVICE, PumpUuid.RECORD_ACCESS_CP, "33690f"))
        assertTrue(allowed(PumpUuid.IDD_SERVICE, PumpUuid.RECORD_ACCESS_CP, "33660f"))
        assertTrue(allowed(PumpUuid.IDD_SERVICE, PumpUuid.RECORD_ACCESS_CP, "5a330f"))
        assertTrue(allowed(PumpUuid.IDD_SERVICE, PumpUuid.RECORD_ACCESS_CP, "335a0f0f41070036410700"))
        // Full 128-bit form of a SIG UUID and lowercase Medtronic UUIDs are the same characteristic.
        assertTrue(allowed(PumpUuid.parse(PumpUuid.CGM_SERVICE).toString(), "00002a52-0000-1000-8000-00805f9b34fb", "0106"))
        for (op in StatusReaderOpcode.entries) {
            assertTrue(allowed(PumpUuid.IDD_SERVICE.lowercase(), PumpUuid.IDD_STATUS_READER_CP, op.request.toHex()), "$op")
        }
    }

    @Test
    fun blocksEverythingElse() {
        // CGM RACP delete / abort
        assertFalse(allowed(PumpUuid.CGM_SERVICE, PumpUuid.RECORD_ACCESS_CP, "0201"))
        assertFalse(allowed(PumpUuid.CGM_SERVICE, PumpUuid.RECORD_ACCESS_CP, "0300"))
        // IDD Status Reader: Reset Status, unknown opcodes, parameters appended
        assertFalse(allowed(PumpUuid.IDD_SERVICE, PumpUuid.IDD_STATUS_READER_CP, "0c03"))
        assertFalse(allowed(PumpUuid.IDD_SERVICE, PumpUuid.IDD_STATUS_READER_CP, "f30300"))
        assertFalse(allowed(PumpUuid.IDD_SERVICE, PumpUuid.IDD_STATUS_READER_CP, "3003"))
        // Command CP (bolus, basal, suspend, settings) – always blocked, even with a "read" opcode
        assertFalse(allowed(PumpUuid.IDD_SERVICE, PumpUuid.IDD_COMMAND_CP, "8e14"))
        // IDD RACP: delete (all / range), abort, other filters, truncated range
        assertFalse(allowed(PumpUuid.IDD_SERVICE, PumpUuid.RECORD_ACCESS_CP, "3c33"))
        assertFalse(allowed(PumpUuid.IDD_SERVICE, PumpUuid.RECORD_ACCESS_CP, "3c330f"))
        assertFalse(allowed(PumpUuid.IDD_SERVICE, PumpUuid.RECORD_ACCESS_CP, "3c5a0f0f41070036410700"))
        assertFalse(allowed(PumpUuid.IDD_SERVICE, PumpUuid.RECORD_ACCESS_CP, "550f"))
        assertFalse(allowed(PumpUuid.IDD_SERVICE, PumpUuid.RECORD_ACCESS_CP, "33693c"))
        assertFalse(allowed(PumpUuid.IDD_SERVICE, PumpUuid.RECORD_ACCESS_CP, "335a0f0f410700"))
        // CGM RACP: only "last record"
        assertFalse(allowed(PumpUuid.CGM_SERVICE, PumpUuid.RECORD_ACCESS_CP, "0101"))
        assertFalse(allowed(PumpUuid.CGM_SERVICE, PumpUuid.RECORD_ACCESS_CP, "0103011000"))
        // CGM specific ops (calibration, session start/stop), session start time write
        assertFalse(allowed(PumpUuid.CGM_SERVICE, PumpUuid.CGM_SPECIFIC_OPS_CP, "1a"))
        assertFalse(allowed(PumpUuid.CGM_SERVICE, PumpUuid.CGM_SESSION_START_TIME, "00"))
        // Same characteristic in a different service must not inherit permissions
        assertFalse(allowed("00000300-0000-1000-0000-009132591325", PumpUuid.RECORD_ACCESS_CP, "0106"))
        assertFalse(allowed("1805", "2A2B", "00"))
    }

    @Test
    fun readAndSubscribeLists() {
        assertTrue(ReadOnlyPolicy.mayRead(PumpUuid.IDD_STATUS.lowercase()))
        assertFalse(ReadOnlyPolicy.mayRead(PumpUuid.IDD_COMMAND_DATA))
        assertTrue(ReadOnlyPolicy.maySubscribe(PumpUuid.CGM_MEASUREMENT))
        assertTrue(ReadOnlyPolicy.maySubscribe("00002aa7-0000-1000-8000-00805f9b34fb"))
        assertFalse(ReadOnlyPolicy.maySubscribe(PumpUuid.IDD_COMMAND_CP))
    }

    @Test
    fun devModeGuard() {
        val on = DevModeGuard(true, "NG1234567H")
        assertTrue(on.accepts("NG1234567H"))
        assertTrue(on.accepts("Pump 1234567H"))
        assertTrue(on.accepts("1234567h"))
        assertFalse(on.accepts("NG7654321H"))
        assertFalse(on.accepts(null))
        assertFalse(DevModeGuard(true, "").accepts("NG1234567H"))
        assertTrue(DevModeGuard(false, "").accepts("NG7654321H"))
    }
}
