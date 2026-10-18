// SPDX-License-Identifier: GPL-3.0-or-later
// HARD RULE 1 (docs/internal/project-brief.md): read only.
//
// Every GATT write towards the pump has to pass this policy. It is an allowlist:
// anything that is not listed here explicitly is blocked. Writes are checked on the
// plaintext, i.e. before SAKE encryption. Characteristic reads and enabling
// notifications/indications do not change the pump state and are handled separately.
//
// Same rules as core/MiniMedKit/Sources/MiniMedKit/Safety/ReadOnlyPolicy.swift; both files
// must stay in sync. Changing this file needs Simon's review. If in doubt whether a message
// writes, it is forbidden.
package de.sgitaize.minimedkit

/** A write the app wants to send to the pump, in plaintext (before encryption). */
class WriteRequest(service: String, characteristic: String, val plaintext: ByteArray) {
    val service: String = PumpUuid.normalize(service)
    val characteristic: String = PumpUuid.normalize(characteristic)
}

/** Result of the policy check: allowed, or blocked with a reason for the log. */
sealed class PolicyDecision {
    data class Allowed(val reason: String) : PolicyDecision()
    data class Blocked(val reason: String) : PolicyDecision()

    val isAllowed: Boolean get() = this is Allowed
}

/**
 * Hard rule 1: the app only reads. Every write to the pump must pass [check]; only
 * report/read requests on the allowlist are allowed, everything else is blocked.
 */
object ReadOnlyPolicy {
    /**
     * Characteristics we may subscribe to (CCCD write). Subscribing only asks the pump to
     * report values and does not change therapy or settings.
     */
    val subscribable: Set<String> = setOf(
        PumpUuid.CGM_MEASUREMENT, PumpUuid.RECORD_ACCESS_CP,
        PumpUuid.IDD_STATUS_READER_CP, PumpUuid.IDD_STATUS_CHANGED,
        PumpUuid.GST_BATTERY_LEVEL, PumpUuid.BATTERY_LEVEL, PumpUuid.IDD_HISTORY_DATA,
    ).map(PumpUuid::normalize).toSet()

    /** Characteristics we may read. */
    val readable: Set<String> = setOf(
        PumpUuid.IDD_STATUS, PumpUuid.IDD_STATUS_CHANGED, PumpUuid.CGM_SESSION_START_TIME,
        PumpUuid.CGM_SESSION_RUN_TIME, PumpUuid.CGM_FEATURE, PumpUuid.SERIAL_NUMBER,
        PumpUuid.FIRMWARE_REVISION, PumpUuid.MODEL_NUMBER, PumpUuid.BATTERY_LEVEL,
        PumpUuid.GST_BATTERY_LEVEL, PumpUuid.SENSOR_EXPIRATION,
    ).map(PumpUuid::normalize).toSet()

    private val cgmService = PumpUuid.normalize(PumpUuid.CGM_SERVICE)
    private val iddService = PumpUuid.normalize(PumpUuid.IDD_SERVICE)
    private val racp = PumpUuid.normalize(PumpUuid.RECORD_ACCESS_CP)
    private val srcp = PumpUuid.normalize(PumpUuid.IDD_STATUS_READER_CP)

    /** Decides whether a write may be sent. Unknown characteristics or opcodes are always blocked. */
    fun check(request: WriteRequest): PolicyDecision {
        val p = request.plaintext
        val s = request.service
        val c = request.characteristic
        return when {
            // CGM Record Access Control Point: only "Report Stored Records" (0x01) with
            // operator Last (0x06). The 780G does not support ">= time offset" (lab notebook).
            // Delete (0x02) and everything else is blocked.
            s == cgmService && c == racp ->
                if (p.contentEquals(bytesOf(0x01, 0x06))) PolicyDecision.Allowed("CGM RACP: letzter Datensatz")
                else PolicyDecision.Blocked("CGM RACP: nicht erlaubter Befehl ${p.toHex()}")

            // IDD Record Access Control Point (pump history, IDS opcodes). Allowed are only
            // the reporting commands with filter type "sequence number" (0x0F), as used by
            // the official app (capture 2): Report Stored Records (0x33) with Last (0x69),
            // First (0x66) or Within Range (0x5A + two u32), and Report Number of Stored
            // Records (0x5A) for All (0x33). Delete Stored Records (0x3C) and Abort (0x55)
            // are blocked. Approved by Simon on 2026-10-15.
            s == iddService && c == racp -> when {
                p.contentEquals(bytesOf(0x33, 0x69, 0x0F)) -> PolicyDecision.Allowed("IDD RACP: letzter History-Eintrag")
                p.contentEquals(bytesOf(0x33, 0x66, 0x0F)) -> PolicyDecision.Allowed("IDD RACP: erster History-Eintrag")
                p.contentEquals(bytesOf(0x5A, 0x33, 0x0F)) -> PolicyDecision.Allowed("IDD RACP: Anzahl History-Einträge")
                p.size == 11 && p.u8(0) == 0x33 && p.u8(1) == 0x5A && p.u8(2) == 0x0F ->
                    PolicyDecision.Allowed("IDD RACP: History-Bereich")
                else -> PolicyDecision.Blocked("IDD RACP: nicht erlaubter Befehl ${p.toHex()}")
            }

            // IDD Status Reader Control Point: only the read-only "Get …" opcodes of
            // StatusReaderOpcode, without parameters. Reset Status (0x030C) is blocked.
            s == iddService && c == srcp -> {
                if (p.size != 2) return PolicyDecision.Blocked("IDD SRCP: unerwartete Länge ${p.size}")
                val opcode = p.u8(0) or (p.u8(1) shl 8)
                val op = StatusReaderOpcode.of(opcode)
                if (op != null) PolicyDecision.Allowed("IDD SRCP: $op")
                else PolicyDecision.Blocked("IDD SRCP: Opcode 0x%04x nicht erlaubt".format(opcode))
            }

            // Includes IDD Command Control Point (bolus, basal, suspend, settings, …),
            // CGM Specific Ops (calibration, session start/stop), session start time
            // writes, History & Trace, NOS, SSE, certificate and firmware services, Current Time.
            else -> PolicyDecision.Blocked("Schreiben auf ${request.characteristic} ist nicht freigegeben")
        }
    }

    /** Whether reading this characteristic is allowed. */
    fun mayRead(characteristic: String): Boolean = PumpUuid.normalize(characteristic) in readable

    /** Whether subscribing to notifications/indications of this characteristic is allowed. */
    fun maySubscribe(characteristic: String): Boolean = PumpUuid.normalize(characteristic) in subscribable
}

/** HARD RULE 2: in DEV_MODE only the test pump is accepted. */
class DevModeGuard(val devMode: Boolean, val testPumpSerial: String) {
    /** Whether the app may talk to a pump with this serial number. */
    fun accepts(serial: String?): Boolean {
        if (!devMode) return true
        if (serial == null || testPumpSerial.isEmpty()) return false
        return normalize(serial) == normalize(testPumpSerial)
    }

    companion object {
        /**
         * The pump reports e.g. "NG1234567X" in DIS or "Pump 1234567X" as device name.
         * We compare the 7 digits + check letter.
         */
        fun normalize(serial: String): String {
            var s = serial.uppercase().trim()
            if (s.startsWith("PUMP ")) s = s.substring(5)
            if (s.startsWith("NG")) s = s.substring(2)
            return s.filter { it.isLetterOrDigit() }
        }
    }
}
