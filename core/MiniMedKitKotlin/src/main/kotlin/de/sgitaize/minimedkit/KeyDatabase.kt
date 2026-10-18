// SPDX-License-Identifier: GPL-3.0-or-later
// SAKE key database. Format and semantics from OpenMinimed (Documentation/key_databases.md).
// The database itself is NOT part of this repository; the app loads it from a local file.
package de.sgitaize.minimedkit

/** SAKE device types (OpenMinimed key_databases.md). */
enum class SakeDeviceType(val raw: Int) {
    INSULIN_PUMP(1),
    GLUCOSE_SENSOR(2),
    BLOOD_GLUCOSE_METER(3),
    MOBILE_APPLICATION(4),
    CARELINK_UPLOAD(5),
    FIRMWARE_UPDATE(6),
    DIAGNOSTIC(7),
    PRIMARY_DISPLAY(8);

    companion object {
        fun of(raw: Int): SakeDeviceType? = entries.firstOrNull { it.raw == raw }
    }
}

/** Static keys for one remote device type, as stored in the key database. */
class StaticKeys(
    val derivationKey: ByteArray,
    val handshakeAuthKey: ByteArray,
    val permitDecryptKey: ByteArray,
    val permitAuthKey: ByteArray,
    val handshakePayload: ByteArray,
)

/** Errors while parsing a key database. */
sealed class KeyDatabaseError(message: String) : Exception(message) {
    object InvalidHex : KeyDatabaseError("invalid hex")
    object TooShort : KeyDatabaseError("too short")
    object CrcMismatch : KeyDatabaseError("crc mismatch")
    object InvalidLength : KeyDatabaseError("invalid length")
    class UnknownDeviceType(val type: Int) : KeyDatabaseError("unknown device type $type")
}

/** SAKE key database: local device type and static keys per remote device type. Loaded at runtime. */
class KeyDatabase(bytes: ByteArray) {
    val localDeviceType: SakeDeviceType
    val remoteDevices: Map<SakeDeviceType, StaticKeys>

    init {
        if (bytes.size < 6) throw KeyDatabaseError.TooShort
        val crc = (bytes.u8(0).toLong() shl 24) or (bytes.u8(1).toLong() shl 16) or
            (bytes.u8(2).toLong() shl 8) or bytes.u8(3).toLong()
        if (Checksums.crc32(bytes.copyOfRange(4, bytes.size)) != crc) throw KeyDatabaseError.CrcMismatch
        val n = bytes.u8(5)
        if (bytes.size != 6 + 81 * n) throw KeyDatabaseError.InvalidLength
        localDeviceType = SakeDeviceType.of(bytes.u8(4)) ?: throw KeyDatabaseError.UnknownDeviceType(bytes.u8(4))
        val remotes = mutableMapOf<SakeDeviceType, StaticKeys>()
        for (i in 0 until n) {
            val p = 6 + 81 * i
            val type = SakeDeviceType.of(bytes.u8(p)) ?: throw KeyDatabaseError.UnknownDeviceType(bytes.u8(p))
            fun k(j: Int) = bytes.copyOfRange(p + 1 + 16 * j, p + 17 + 16 * j)
            remotes[type] = StaticKeys(k(0), k(1), k(2), k(3), k(4))
        }
        remoteDevices = remotes
    }

    companion object {
        /** Parses the database from hex text; whitespace is ignored. */
        fun fromHex(hex: String): KeyDatabase = KeyDatabase(hexToBytes(hex) ?: throw KeyDatabaseError.InvalidHex)

        /**
         * Finds a database in a text: plain hex, or a page with several hex blocks such as
         * OpenMinimed's key_databases.md (blocks in <code>…</code>, hex groups separated by
         * spaces). Returns the hex of the first block that parses and passes [accept].
         */
        fun findHex(text: String, accept: (KeyDatabase) -> Boolean): String? {
            val candidates = Regex("<code>(.*?)</code>", RegexOption.DOT_MATCHES_ALL)
                .findAll(text).map { it.groupValues[1] }.toMutableList()
            candidates.add(text)
            for (candidate in candidates) {
                val clean = candidate.filterNot { it.isWhitespace() }
                if (clean.isEmpty() || !clean.all { it in '0'..'9' || it.lowercaseChar() in 'a'..'f' }) continue
                val db = try { fromHex(clean) } catch (e: KeyDatabaseError) { continue }
                if (accept(db)) return clean
            }
            return null
        }

        /** The database the app needs: local "Mobile Application" with keys for the insulin pump. */
        fun isMobilePump(db: KeyDatabase): Boolean =
            db.localDeviceType == SakeDeviceType.MOBILE_APPLICATION && db.remoteDevices[SakeDeviceType.INSULIN_PUMP] != null
    }
}
