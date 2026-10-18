// SPDX-License-Identifier: GPL-3.0-or-later
// SAKE handshake (server role) and session cipher. Kotlin port of the Swift package
// (itself a port of OpenMinimed PythonSake/JavaSake, GPL-3.0).
//
// Roles: the phone app is the BLE peripheral and SAKE server, the pump is the client.
// Stages: 0 (20 zero bytes in → msg0 out) → 1 (msg1 in → msg2 out)
//         → 3 (msg3 in → msg4 out) → 5 (msg5 in → done) → 6
//
// SeqCrypt wire format: ciphertext || seqByte || cmac4[0..<2]
// IV/CMAC prefix: seq (5 bytes BE) || sessionNonce (8 bytes) || 00 00 00
package de.sgitaize.minimedkit

import java.security.SecureRandom

/** Errors of the SAKE handshake and the session cipher. */
sealed class SakeError(message: String) : Exception(message) {
    class InvalidMessageLength(val length: Int) : SakeError("invalid message length $length")
    object UnexpectedHandshakeStart : SakeError("unexpected handshake start")
    class UnexpectedDeviceType(val type: Int) : SakeError("unexpected device type $type")
    object MissingStaticKeys : SakeError("missing static keys")
    class MacFailure(val where: String) : SakeError("mac failure: $where")
    object PermitRejected : SakeError("permit rejected")
    object HandshakeAlreadyComplete : SakeError("handshake already complete")
    object SequenceExhausted : SakeError("sequence exhausted")
}

/** Source of random bytes (injectable for tests with captured handshakes). */
fun interface RandomSource {
    fun bytes(count: Int): ByteArray
}

/** Cryptographically secure random bytes from the system. */
class SystemRandom : RandomSource {
    private val random = SecureRandom()
    override fun bytes(count: Int): ByteArray = ByteArray(count).also { random.nextBytes(it) }
}

/**
 * SAKE session cipher: AES-CTR with a sequence number in the nonce and a truncated AES-CMAC
 * (2 bytes). Separate counters for sending and receiving.
 */
class SeqCrypt internal constructor(val key: ByteArray, val nonce: ByteArray, initialSeq: Long) {
    var txSeq: Long = initialSeq
        internal set
    var rxSeq: Long = initialSeq
        internal set

    init {
        require(key.size == 16 && nonce.size == 8)
    }

    /** Snapshot of the session cipher, so a session can survive an app restart. */
    data class State(val key: ByteArray, val nonce: ByteArray, val txSeq: Long, val rxSeq: Long) {
        /** Compact text form for storage: `key:nonce:tx:rx` (hex, decimal). */
        fun encode(): String = "${key.toHex()}:${nonce.toHex()}:$txSeq:$rxSeq"

        override fun equals(other: Any?): Boolean = other is State && key.contentEquals(other.key) &&
            nonce.contentEquals(other.nonce) && txSeq == other.txSeq && rxSeq == other.rxSeq

        override fun hashCode(): Int = encode().hashCode()

        companion object {
            fun decode(text: String): State? {
                val p = text.trim().split(":")
                if (p.size != 4) return null
                val key = hexToBytes(p[0]) ?: return null
                val nonce = hexToBytes(p[1]) ?: return null
                return State(key, nonce, p[2].toLongOrNull() ?: return null, p[3].toLongOrNull() ?: return null)
            }
        }
    }

    val state: State get() = State(key.copyOf(), nonce.copyOf(), txSeq, rxSeq)

    /** Encrypts and authenticates a message and advances the send counter. */
    fun encrypt(plaintext: ByteArray): ByteArray {
        val seq = txSeq
        if (seq >= MAX_SEQ) throw SakeError.SequenceExhausted
        val iv = prefix(seq, nonce)
        val ciphertext = AES128.ctr(key, iv, plaintext)
        val tag = AES128.cmac(key, iv + ciphertext, 4)
        txSeq = seq + 2
        return ciphertext + byteArrayOf(((seq shr 1) and 0xFF).toByte(), tag[0], tag[1])
    }

    /** Checks and decrypts a message; accepts sequence numbers slightly ahead of the receive counter. */
    fun decrypt(message: ByteArray): ByteArray {
        if (message.size < 3) throw SakeError.InvalidMessageLength(message.size)
        val seqByte = message.u8(message.size - 3)
        val delta = (seqByte - ((rxSeq shr 1) and 0xFF).toInt()) and 0xFF
        if (delta > MAX_RX_DELTA) throw SakeError.MacFailure("sequence delta $delta out of window")
        val seq = rxSeq + 2L * delta
        val ciphertext = message.copyOf(message.size - 3)
        val iv = prefix(seq, nonce)
        val tag = AES128.cmac(key, iv + ciphertext, 4)
        // rxSeq only advances on success, see JavaSake PR #2.
        if (!constantTimeEqual(tag.copyOf(2), message.copyOfRange(message.size - 2, message.size))) {
            throw SakeError.MacFailure("seq $seq")
        }
        rxSeq = seq + 2
        return AES128.ctr(key, iv, ciphertext)
    }

    companion object {
        const val MAX_RX_DELTA = 128
        const val MAX_SEQ = 1L shl 40

        fun fromState(state: State): SeqCrypt? {
            if (state.key.size != 16 || state.nonce.size != 8) return null
            return SeqCrypt(state.key.copyOf(), state.nonce.copyOf(), 0).also {
                it.txSeq = state.txSeq
                it.rxSeq = state.rxSeq
            }
        }

        internal fun prefix(seq: Long, nonce: ByteArray): ByteArray {
            val block = ByteArray(16)
            for (i in 0 until 5) block[i] = ((seq shr (8 * (4 - i))) and 0xFF).toByte()
            for (i in 0 until 8) block[5 + i] = nonce[i]
            return block
        }
    }
}

/**
 * Server side of the SAKE handshake (the phone; the pump is the client). Six 20-byte
 * messages; afterwards [crypt] encrypts the session.
 */
class SakeServer(
    private val keyDatabase: KeyDatabase,
    private val localDeviceType: SakeDeviceType = SakeDeviceType.MOBILE_APPLICATION,
    private val random: RandomSource = SystemRandom(),
) {
    internal var msg4Pad: Int = DEFAULT_MSG4_PAD

    var stage = 0
        private set
    val isComplete: Boolean get() = stage == 6

    private var clientDeviceType: SakeDeviceType? = null
    private var clientKeyMaterial = ByteArray(0)
    private var clientNonce = ByteArray(0)
    private var serverKeyMaterial = ByteArray(0)
    private var serverNonce = ByteArray(0)
    private var staticKeys: StaticKeys? = null

    /**
     * Session cipher after the handshake. The server uses one SeqCrypt for both
     * directions (separate tx/rx counters), as in the reference implementation.
     */
    var crypt: SeqCrypt? = null
        private set

    /**
     * Feeds one message written by the pump into the handshake.
     * Returns the message to notify back, or null when the handshake completed.
     */
    fun handle(input: ByteArray): ByteArray? {
        if (input.size != MESSAGE_SIZE) throw SakeError.InvalidMessageLength(input.size)
        when (stage) {
            0 -> {
                if (!input.all { it.toInt() == 0 }) throw SakeError.UnexpectedHandshakeStart
                stage = 1
                return byteArrayOf(localDeviceType.raw.toByte(), 0x01) + random.bytes(18)
            }
            1 -> {
                clientKeyMaterial = input.copyOfRange(0, 8)
                val type = SakeDeviceType.of(input.u8(8)) ?: throw SakeError.UnexpectedDeviceType(input.u8(8))
                clientDeviceType = type
                clientNonce = input.copyOfRange(9, 13)
                if (keyDatabase.localDeviceType != localDeviceType) throw SakeError.MissingStaticKeys
                val keys = keyDatabase.remoteDevices[type] ?: throw SakeError.MissingStaticKeys
                staticKeys = keys

                serverKeyMaterial = random.bytes(8)
                serverNonce = random.bytes(4)
                val tag = cmac8(keys, serverKeyMaterial + clientKeyMaterial + keys.derivationKey)
                stage = 3
                return tag + serverKeyMaterial + serverNonce
            }
            3 -> {
                val keys = staticKeys ?: throw SakeError.MissingStaticKeys
                val serverTag = cmac8(keys, serverKeyMaterial + clientKeyMaterial + keys.derivationKey)
                val expected = cmac8(keys, serverTag + serverKeyMaterial + keys.derivationKey)
                if (!constantTimeEqual(expected, input.copyOfRange(0, 8))) throw SakeError.MacFailure("handshake msg3")
                val sessionKey = AES128.encryptBlock(keys.derivationKey, serverKeyMaterial + clientKeyMaterial)
                val c = SeqCrypt(sessionKey, clientNonce + serverNonce, 1)
                crypt = c
                stage = 5
                return c.encrypt(keys.handshakePayload + byteArrayOf(msg4Pad.toByte()))
            }
            5 -> {
                val keys = staticKeys ?: throw SakeError.MissingStaticKeys
                val c = crypt ?: throw SakeError.MissingStaticKeys
                val client = clientDeviceType ?: throw SakeError.MissingStaticKeys
                // msg5 is encrypted with the client's sequence parity (even, starting at 0).
                val clientCrypt = SeqCrypt(c.key, c.nonce, 0)
                val plain = clientCrypt.decrypt(input)
                val permit = AES128.decryptBlock(keys.permitDecryptKey, plain.copyOf(16))
                val tag = AES128.cmac(keys.permitAuthKey, permit.copyOf(12), 4)
                if (!constantTimeEqual(tag, permit.copyOfRange(12, 16))) throw SakeError.MacFailure("permit")
                if (permit.u8(0) != 0 || permit.u8(1) != client.raw) throw SakeError.PermitRejected
                // Align rx with the native shared counter (see pysake server.py, stage 5).
                c.rxSeq = 2
                stage = 6
                return null
            }
            else -> throw SakeError.HandshakeAlreadyComplete
        }
    }

    private fun cmac8(keys: StaticKeys, message: ByteArray): ByteArray = AES128.cmac(keys.handshakeAuthKey, message, 8)

    companion object {
        const val MESSAGE_SIZE = 20
        const val DEFAULT_MSG4_PAD = 0x69
    }
}
