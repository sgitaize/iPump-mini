// SPDX-License-Identifier: GPL-3.0-or-later
package de.sgitaize.minimedkit

/** Unsigned byte at [index] as Int (0…255). */
fun ByteArray.u8(index: Int): Int = this[index].toInt() and 0xFF

/** Lowercase hex without separators, like `[UInt8].hex` in the Swift package. */
fun ByteArray.toHex(): String = joinToString("") { "%02x".format(it.toInt() and 0xFF) }

/** Parses hex, ignoring whitespace. Returns null on invalid input. */
fun hexToBytes(hex: String): ByteArray? {
    val clean = hex.filterNot { it.isWhitespace() }
    if (clean.length % 2 != 0) return null
    val out = ByteArray(clean.length / 2)
    for (i in out.indices) {
        val hi = Character.digit(clean[2 * i], 16)
        val lo = Character.digit(clean[2 * i + 1], 16)
        if (hi < 0 || lo < 0) return null
        out[i] = ((hi shl 4) or lo).toByte()
    }
    return out
}

/** Builds a ByteArray from Int values (0…255), for readable constants. */
fun bytesOf(vararg values: Int): ByteArray = ByteArray(values.size) { values[it].toByte() }

/** Little-endian u32 as 4 bytes (IDD RACP sequence numbers). */
fun le32(value: Long): ByteArray = ByteArray(4) { ((value shr (8 * it)) and 0xFF).toByte() }

/** Errors while parsing pump payloads. */
sealed class ParseError(message: String) : Exception(message) {
    object TooShort : ParseError("too short")
    object CrcMismatch : ParseError("crc mismatch")
    class UnexpectedOpcode(val opcode: Int) : ParseError("unexpected opcode 0x%04x".format(opcode))
    object LengthMismatch : ParseError("length mismatch")
    class TrailingBytes(val count: Int) : ParseError("$count trailing bytes")
}

/** Little-endian reader for GATT payloads. */
internal class ByteReader(private val bytes: ByteArray) {
    var offset = 0
        private set

    val remaining: Int get() = bytes.size - offset

    fun u8(): Int {
        if (remaining < 1) throw ParseError.TooShort
        return bytes.u8(offset).also { offset += 1 }
    }

    fun i8(): Int = u8().toByte().toInt()

    fun u16(): Int {
        if (remaining < 2) throw ParseError.TooShort
        return (bytes.u8(offset) or (bytes.u8(offset + 1) shl 8)).also { offset += 2 }
    }

    fun u32(): Long {
        if (remaining < 4) throw ParseError.TooShort
        var v = 0L
        for (i in 0 until 4) v = v or (bytes.u8(offset + i).toLong() shl (8 * i))
        offset += 4
        return v
    }

    /** IEEE-11073 16-bit SFLOAT (4-bit exponent, 12-bit mantissa). */
    fun sfloat(): Double = MedFloat.decode16(u16())

    /** IEEE-11073 32-bit FLOAT (8-bit exponent, 24-bit mantissa). */
    fun float32(): Double = MedFloat.decode32(u32())

    fun expectEnd() {
        if (remaining > 0) throw ParseError.TrailingBytes(remaining)
    }
}

/** IEEE-11073 SFLOAT (16 bit) and FLOAT (32 bit), as used by the Bluetooth health services. */
object MedFloat {
    /** Decodes an SFLOAT: 12-bit mantissa, 4-bit exponent (base 10). */
    fun decode16(raw: Int): Double {
        var e = (raw shr 12) and 0x0F
        var m = raw and 0x0FFF
        if (e >= 0x8) e -= 0x10
        if (m >= 0x800) m -= 0x1000
        return scaled(m, e)
    }

    /** Decodes a FLOAT: 24-bit mantissa, 8-bit exponent (base 10). */
    fun decode32(raw: Long): Double {
        var e = ((raw shr 24) and 0xFF).toInt()
        var m = (raw and 0x00FF_FFFF).toInt()
        if (e >= 0x80) e -= 0x100
        if (m >= 0x80_0000) m -= 0x100_0000
        return scaled(m, e)
    }

    /** Avoids binary rounding noise such as 1.1600000000000001. */
    private fun scaled(m: Int, e: Int): Double = "${m}e$e".toDouble()
}
