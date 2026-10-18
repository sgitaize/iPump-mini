// SPDX-License-Identifier: GPL-3.0-or-later
// Test vectors: OpenMinimed PythonSake/JavaSake (captured 780G pairing, GPL-3.0),
// identical to core/MiniMedKit/Tests/MiniMedKitTests/SakeTests.swift.
package de.sgitaize.minimedkit

import org.junit.Assume.assumeTrue
import org.junit.Test
import java.io.File
import kotlin.test.assertContentEquals
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue

internal fun hex(s: String): ByteArray = hexToBytes(s)!!

/** Repository root (set by Gradle), for the gitignored `_vendor/keys/` folder. */
internal fun repoFile(path: String): File = File(System.getProperty("omp.repoRoot") ?: "../..", path)

/** Loads the Mobile↔Pump key database from `_vendor/keys/`; skips the test if it is missing. */
internal fun loadPumpKeyDatabase(): KeyDatabase {
    val file = repoFile("_vendor/keys/mobile-pump.keydb.hex")
    assumeTrue("Schlüsseldatenbank fehlt: ${file.path} (siehe docs/de/selbst-bauen.md)", file.exists())
    return KeyDatabase.fromHex(file.readText())
}

private class QueuedRandom(vararg chunks: ByteArray) : RandomSource {
    private val queue = ArrayDeque(chunks.toList())
    override fun bytes(count: Int): ByteArray = queue.removeFirst().also { check(it.size == count) }
}

class SakeTest {
    private val pumpTrace = listOf(
        "0401e2f09017a98f9f01cc56492fbacd4576e92b",
        "42060e9f344e9312016ee8854d357f659b6b00ba",
        "fdeeb13d04c3f18d272630ebeabe7c3a4d4d27b9",
        "c02cec4ffb99affcb553a10fa6c55bb13d9fbacf",
        "157d8e90214418a0e3d5f0517eebf4a82e00c02e",
        "9b36f393b296fa84a757809859fc84a5c300d59b",
    ).map(::hex)

    @Test
    fun cmacMatchesRfc4493() {
        val key = hex("2b7e151628aed2a6abf7158809cf4f3c")
        assertEquals("bb1d6929e95937287fa37d129b756746", AES128.cmac(key, ByteArray(0)).toHex())
        assertEquals("070a16b46b4d4144f79bdd9dd04a287c", AES128.cmac(key, hex("6bc1bee22e409f96e93d7e117393172a")).toHex())
        val m40 = hex("6bc1bee22e409f96e93d7e117393172aae2d8a571e03ac9c9eb76fac45af8e5130c81c46a35ce411")
        assertEquals("dfa66747de9ae63030ca32611497c827", AES128.cmac(key, m40).toHex())
    }

    @Test
    fun seqCryptMatchesReference() {
        val key = hex("00112233445566778899aabbccddeeff")
        val nonce = hex("a1b2c3d4e5f60718")
        val plain0 = hex("00000000000000000000000000000000ff")
        val plain1 = hex("48656c6c6f2c2053414b65212121212121")
        val plain2 = hex("deadbeef")

        val tx = SeqCrypt(key, nonce, 0)
        assertEquals("7680ea16798357df88b11466330e24d3f200b0e6", tx.encrypt(plain0).toHex())
        assertEquals("9b92fdd551a0cbfc63b5fae41e888ca53c011265", tx.encrypt(plain1).toHex())
        assertEquals("60c26e3b02e1a3", tx.encrypt(plain2).toHex())

        val server = SeqCrypt(key, nonce, 1)
        assertEquals("28b3469d0ece854f9760df0c7be2e79d93006a3d", server.encrypt(plain1).toHex())

        val rx = SeqCrypt(key, nonce, 0)
        assertContentEquals(plain0, rx.decrypt(hex("7680ea16798357df88b11466330e24d3f200b0e6")))
        // A skipped message is tolerated (reorder window).
        assertContentEquals(plain2, rx.decrypt(hex("60c26e3b02e1a3")))
        assertEquals(6, rx.rxSeq)
    }

    @Test
    fun seqCryptRejectsTamperingWithoutAdvancing() {
        val rx = SeqCrypt(hex("00112233445566778899aabbccddeeff"), hex("a1b2c3d4e5f60718"), 0)
        val bad = hex("7680ea16798357df88b11466330e24d3f200b0e6")
        bad[0] = (bad[0].toInt() xor 1).toByte()
        assertFailsWith<SakeError> { rx.decrypt(bad) }
        assertEquals(0, rx.rxSeq)
    }

    @Test
    fun seqCryptStateRoundTrip() {
        val a = SeqCrypt(hex("00112233445566778899aabbccddeeff"), hex("a1b2c3d4e5f60718"), 1)
        a.encrypt(bytesOf(1, 2, 3))
        val b = SeqCrypt.fromState(SeqCrypt.State.decode(a.state.encode())!!)!!
        assertEquals(3, b.txSeq)
        assertContentEquals(a.encrypt(bytesOf(4)), b.encrypt(bytesOf(4)))
    }

    @Test
    fun keyDatabaseRejectsCorruption() {
        val bytes = hex("f75995e7040101" + "00".repeat(80))
        assertFailsWith<KeyDatabaseError.CrcMismatch> { KeyDatabase(bytes) }
        assertFailsWith<KeyDatabaseError> { KeyDatabase(bytes.copyOf(bytes.size - 1)) }
    }

    @Test
    fun serverReproducesCapturedPumpHandshake() {
        val db = loadPumpKeyDatabase()
        assertEquals(SakeDeviceType.MOBILE_APPLICATION, db.localDeviceType)
        val random = QueuedRandom(
            pumpTrace[0].copyOfRange(2, 20),
            pumpTrace[2].copyOfRange(8, 16),
            pumpTrace[2].copyOfRange(16, 20),
        )
        val server = SakeServer(db, random = random)
        server.msg4Pad = 0xF7 // pad byte of the captured trace (JavaSake SakeServerTest)

        assertContentEquals(pumpTrace[0], server.handle(ByteArray(20)))
        assertContentEquals(pumpTrace[2], server.handle(pumpTrace[1]))
        assertContentEquals(pumpTrace[4], server.handle(pumpTrace[3]))
        assertNull(server.handle(pumpTrace[5]))
        assertTrue(server.isComplete)
        assertEquals(3, server.crypt?.txSeq)
        assertEquals(2, server.crypt?.rxSeq)
    }

    @Test
    fun serverRejectsForgedClientAuth() {
        val server = SakeServer(loadPumpKeyDatabase())
        server.handle(ByteArray(20))
        server.handle(pumpTrace[1])
        // msg3 from the trace does not match our fresh random key material.
        assertFailsWith<SakeError> { server.handle(pumpTrace[3]) }
        assertFalse(server.isComplete)
    }

    @Test
    fun serverRejectsNonZeroStart() {
        val server = SakeServer(loadPumpKeyDatabase())
        assertFailsWith<SakeError> { server.handle(pumpTrace[1]) }
        assertFailsWith<SakeError> { server.handle(bytesOf(0)) }
    }
}

class KeyDatabaseFindTest {
    @Test
    fun ignoresNonHexAndGarbage() {
        assertNull(KeyDatabase.findHex("<code>0x0001dcf0</code> hello") { true })
        assertNull(KeyDatabase.findHex("") { true })
    }

    /**
     * The published page (copy in the gitignored _vendor/keys/) contains several databases;
     * the pump database must be picked and must equal the local one.
     */
    @Test
    fun findsPumpDatabaseOnOpenMinimedPage() {
        val page = repoFile("_vendor/keys/key_databases.md")
        val local = repoFile("_vendor/keys/mobile-pump.keydb.hex")
        assumeTrue("_vendor/keys/key_databases.md oder mobile-pump.keydb.hex fehlt", page.exists() && local.exists())
        val expected = local.readText().filterNot { it.isWhitespace() }.lowercase()
        assertEquals(expected, KeyDatabase.findHex(page.readText(), KeyDatabase::isMobilePump)?.lowercase())
        assertEquals(expected, KeyDatabase.findHex(local.readText().replace("0", "0 "), KeyDatabase::isMobilePump)?.lowercase())
    }
}
