// SPDX-License-Identifier: GPL-3.0-or-later
// AES-128 primitives (ECB block, CTR, CMAC) on top of javax.crypto, and the checksums.
package de.sgitaize.minimedkit

import javax.crypto.Cipher
import javax.crypto.spec.SecretKeySpec

/** Errors of the AES wrappers. */
class CryptoError(message: String) : Exception(message)

internal object AES128 {
    const val BLOCK_SIZE = 16

    fun encryptBlock(key: ByteArray, block: ByteArray): ByteArray = crypt(Cipher.ENCRYPT_MODE, key, block)

    fun decryptBlock(key: ByteArray, block: ByteArray): ByteArray = crypt(Cipher.DECRYPT_MODE, key, block)

    private fun crypt(mode: Int, key: ByteArray, block: ByteArray): ByteArray {
        if (key.size != 16) throw CryptoError("invalid key length")
        if (block.size != BLOCK_SIZE) throw CryptoError("invalid block length")
        val cipher = Cipher.getInstance("AES/ECB/NoPadding")
        cipher.init(mode, SecretKeySpec(key, "AES"))
        return cipher.doFinal(block)
    }

    /**
     * AES-CTR with a 16-byte initial counter block. The counter is the whole block
     * interpreted as a big-endian integer (same as PyCryptodome/BouncyCastle for our sizes).
     */
    fun ctr(key: ByteArray, iv: ByteArray, data: ByteArray): ByteArray {
        if (iv.size != BLOCK_SIZE) throw CryptoError("invalid block length")
        val counter = iv.copyOf()
        val out = ByteArray(data.size)
        var offset = 0
        while (offset < data.size) {
            val keystream = encryptBlock(key, counter)
            val n = minOf(BLOCK_SIZE, data.size - offset)
            for (i in 0 until n) out[offset + i] = (data[offset + i].toInt() xor keystream[i].toInt()).toByte()
            offset += n
            increment(counter)
        }
        return out
    }

    private fun increment(block: ByteArray) {
        for (i in block.indices.reversed()) {
            block[i] = (block[i] + 1).toByte()
            if (block[i].toInt() != 0) break
        }
    }

    /** AES-CMAC (RFC 4493), truncated to [length] bytes. */
    fun cmac(key: ByteArray, message: ByteArray, length: Int = 16): ByteArray {
        val zero = ByteArray(BLOCK_SIZE)
        val l = encryptBlock(key, zero)
        val k1 = subkey(l)
        val k2 = subkey(k1)

        val blocks = maxOf(1, (message.size + BLOCK_SIZE - 1) / BLOCK_SIZE)
        val complete = message.isNotEmpty() && message.size % BLOCK_SIZE == 0
        val last = ByteArray(BLOCK_SIZE)
        val lastStart = (blocks - 1) * BLOCK_SIZE
        if (complete) {
            for (i in 0 until BLOCK_SIZE) last[i] = (message[lastStart + i].toInt() xor k1[i].toInt()).toByte()
        } else {
            val rest = message.size - lastStart
            for (i in 0 until rest) last[i] = message[lastStart + i]
            last[rest] = 0x80.toByte()
            for (i in 0 until BLOCK_SIZE) last[i] = (last[i].toInt() xor k2[i].toInt()).toByte()
        }

        var x = zero
        for (b in 0 until blocks - 1) {
            val y = ByteArray(BLOCK_SIZE) { (x[it].toInt() xor message[b * BLOCK_SIZE + it].toInt()).toByte() }
            x = encryptBlock(key, y)
        }
        val y = ByteArray(BLOCK_SIZE) { (x[it].toInt() xor last[it].toInt()).toByte() }
        return encryptBlock(key, y).copyOf(length)
    }

    private fun subkey(input: ByteArray): ByteArray {
        val out = ByteArray(BLOCK_SIZE)
        var carry = 0
        for (i in BLOCK_SIZE - 1 downTo 0) {
            val v = input[i].toInt() and 0xFF
            out[i] = ((v shl 1) or carry).toByte()
            carry = v shr 7
        }
        if (input[0].toInt() and 0x80 != 0) out[BLOCK_SIZE - 1] = (out[BLOCK_SIZE - 1].toInt() xor 0x87).toByte()
        return out
    }
}

/** Constant-time comparison for MAC tags. */
internal fun constantTimeEqual(a: ByteArray, b: ByteArray): Boolean {
    if (a.size != b.size) return false
    var diff = 0
    for (i in a.indices) diff = diff or (a[i].toInt() xor b[i].toInt())
    return diff == 0
}

/** CRC-32 (key database) and the Bluetooth E2E-CRC (CRC-16/CCITT-FALSE) used by CGM and IDD records. */
object Checksums {
    /** CRC-32 (IEEE 802.3, zlib), used for the SAKE key database header. */
    fun crc32(data: ByteArray): Long {
        val crc = java.util.zip.CRC32()
        crc.update(data)
        return crc.value
    }

    /** E2E-CRC of the Bluetooth medical profiles: CRC-16/CCITT-FALSE (poly 0x1021, init 0xFFFF). */
    fun e2eCrc(data: ByteArray): Int {
        var crc = 0xFFFF
        for (byte in data) {
            crc = crc xor ((byte.toInt() and 0xFF) shl 8)
            repeat(8) {
                crc = if (crc and 0x8000 != 0) ((crc shl 1) xor 0x1021) and 0xFFFF else (crc shl 1) and 0xFFFF
            }
        }
        return crc
    }

    /** Checks a payload whose last two bytes are a little-endian E2E-CRC. */
    fun hasValidE2eCrc(message: ByteArray): Boolean {
        if (message.size < 2) return false
        val body = message.copyOf(message.size - 2)
        val received = message.u8(message.size - 2) or (message.u8(message.size - 1) shl 8)
        return e2eCrc(body) == received
    }
}
