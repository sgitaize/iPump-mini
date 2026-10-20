// SPDX-License-Identifier: GPL-3.0-or-later
// GATT UUIDs of the 700-series pump and of the app side (OpenMinimed Documentation).
package de.sgitaize.minimedkit

import java.util.UUID

/**
 * Service and characteristic UUIDs of the 780G (Bluetooth SIG and Medtronic base UUID).
 * SIG UUIDs are kept in their 16-bit short form ("2A52"), Medtronic UUIDs in full form;
 * [PumpUuid.short] turns a java.util.UUID into the same notation.
 */
object PumpUuid {
    private fun mdt(short: String) = "0000$short-0000-1000-0000-009132591325"

    // App side (we host these as BLE peripheral)
    const val SAKE_SERVICE = "FE82"
    const val RECONNECT_SERVICE = "FE81"
    val SAKE_PORT = mdt("FE82")
    val APP_DEVICE_INFO_SERVICE = mdt("0900")

    // Pump: Insulin Delivery Service (Medtronic UUIDs)
    val IDD_SERVICE = mdt("0100")
    val IDD_STATUS_CHANGED = mdt("0101")
    val IDD_STATUS = mdt("0102")
    val IDD_ANNUNCIATION = mdt("0103")
    val IDD_FEATURES = mdt("0104")
    val IDD_STATUS_READER_CP = mdt("0105")
    val IDD_COMMAND_CP = mdt("0106")
    val IDD_COMMAND_DATA = mdt("0107")
    val IDD_HISTORY_DATA = mdt("0108")
    val GST_BATTERY_LEVEL = mdt("0400")

    // Pump: CGM service (SIG UUIDs + Medtronic extensions)
    const val CGM_SERVICE = "181F"
    const val CGM_MEASUREMENT = "2AA7"
    const val CGM_FEATURE = "2AA8"
    const val CGM_STATUS = "2AA9"
    const val CGM_SESSION_START_TIME = "2AAA"
    const val CGM_SESSION_RUN_TIME = "2AAB"
    const val CGM_SPECIFIC_OPS_CP = "2AAC"
    val SENSOR_EXPIRATION = mdt("0202")

    // Shared
    const val RECORD_ACCESS_CP = "2A52"
    const val DEVICE_INFO_SERVICE = "180A"
    const val SERIAL_NUMBER = "2A25"
    const val FIRMWARE_REVISION = "2A26"
    const val MODEL_NUMBER = "2A24"
    const val BATTERY_SERVICE = "180F"
    const val BATTERY_LEVEL = "2A19"

    /** Client Characteristic Configuration descriptor. */
    const val CCCD = "2902"

    private const val SIG_SUFFIX = "-0000-1000-8000-00805F9B34FB"

    /** Uppercase short form for SIG UUIDs ("2A52"), uppercase full form otherwise. */
    fun short(uuid: UUID): String {
        val s = uuid.toString().uppercase()
        return if (s.startsWith("0000") && s.endsWith(SIG_SUFFIX)) s.substring(4, 8) else s
    }

    /** Normalises a UUID string (short or full, any case) to the notation of [short]. */
    fun normalize(uuid: String): String =
        try { short(parse(uuid.trim())) } catch (e: IllegalArgumentException) { uuid.trim().uppercase() }

    /** java.util.UUID for a short SIG UUID ("2A52") or a full UUID string. */
    fun parse(uuid: String): UUID =
        if (uuid.length == 4) UUID.fromString("0000$uuid$SIG_SUFFIX") else UUID.fromString(uuid)
}
