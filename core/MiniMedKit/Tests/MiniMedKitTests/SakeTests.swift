// SPDX-License-Identifier: GPL-3.0-or-later
// Test vectors: OpenMinimed PythonSake/JavaSake (captured 780G pairing, GPL-3.0).
import XCTest
@testable import MiniMedKit

/// Loads the Mobile↔Pump key database from the gitignored `_vendor/keys/` folder.
func loadPumpKeyDatabase() throws -> KeyDatabase {
    let repo = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent()
    let url = repo.appendingPathComponent("_vendor/keys/mobile-pump.keydb.hex")
    guard let hex = try? String(contentsOf: url, encoding: .utf8) else {
        throw XCTSkip("Schlüsseldatenbank fehlt: \(url.path) (siehe docs/de/selbst-bauen.md)")
    }
    return try KeyDatabase(hex: hex)
}

struct QueuedRandom: RandomSource {
    final class Box { var chunks: [[UInt8]]; init(_ c: [[UInt8]]) { chunks = c } }
    let box: Box
    init(_ chunks: [[UInt8]]) { box = Box(chunks) }
    func bytes(_ count: Int) -> [UInt8] {
        let next = box.chunks.removeFirst()
        precondition(next.count == count)
        return next
    }
}

final class SakeTests: XCTestCase {
    let pumpTrace: [[UInt8]] = [
        "0401e2f09017a98f9f01cc56492fbacd4576e92b",
        "42060e9f344e9312016ee8854d357f659b6b00ba",
        "fdeeb13d04c3f18d272630ebeabe7c3a4d4d27b9",
        "c02cec4ffb99affcb553a10fa6c55bb13d9fbacf",
        "157d8e90214418a0e3d5f0517eebf4a82e00c02e",
        "9b36f393b296fa84a757809859fc84a5c300d59b",
    ].map { [UInt8](hex: $0)! }

    func testCMACMatchesRFC4493() throws {
        let key = [UInt8](hex: "2b7e151628aed2a6abf7158809cf4f3c")!
        XCTAssertEqual(try AES128.cmac(key: key, message: []).hex, "bb1d6929e95937287fa37d129b756746")
        let m16 = [UInt8](hex: "6bc1bee22e409f96e93d7e117393172a")!
        XCTAssertEqual(try AES128.cmac(key: key, message: m16).hex, "070a16b46b4d4144f79bdd9dd04a287c")
        let m40 = [UInt8](hex: "6bc1bee22e409f96e93d7e117393172aae2d8a571e03ac9c9eb76fac45af8e5130c81c46a35ce411")!
        XCTAssertEqual(try AES128.cmac(key: key, message: m40).hex, "dfa66747de9ae63030ca32611497c827")
    }

    func testSeqCryptMatchesReference() throws {
        let key = [UInt8](hex: "00112233445566778899aabbccddeeff")!
        let nonce = [UInt8](hex: "a1b2c3d4e5f60718")!
        let plain0 = [UInt8](hex: "00000000000000000000000000000000ff")!
        let plain1 = [UInt8](hex: "48656c6c6f2c2053414b65212121212121")!
        let plain2 = [UInt8](hex: "deadbeef")!

        let tx = SeqCrypt(key: key, nonce: nonce, initialSeq: 0)
        XCTAssertEqual(try tx.encrypt(plain0).hex, "7680ea16798357df88b11466330e24d3f200b0e6")
        XCTAssertEqual(try tx.encrypt(plain1).hex, "9b92fdd551a0cbfc63b5fae41e888ca53c011265")
        XCTAssertEqual(try tx.encrypt(plain2).hex, "60c26e3b02e1a3")

        let server = SeqCrypt(key: key, nonce: nonce, initialSeq: 1)
        XCTAssertEqual(try server.encrypt(plain1).hex, "28b3469d0ece854f9760df0c7be2e79d93006a3d")

        let rx = SeqCrypt(key: key, nonce: nonce, initialSeq: 0)
        XCTAssertEqual(try rx.decrypt([UInt8](hex: "7680ea16798357df88b11466330e24d3f200b0e6")!), plain0)
        // A skipped message is tolerated (reorder window).
        XCTAssertEqual(try rx.decrypt([UInt8](hex: "60c26e3b02e1a3")!), plain2)
        XCTAssertEqual(rx.rxSeq, 6)
    }

    func testSeqCryptRejectsTamperingWithoutAdvancing() throws {
        let key = [UInt8](hex: "00112233445566778899aabbccddeeff")!
        let nonce = [UInt8](hex: "a1b2c3d4e5f60718")!
        let rx = SeqCrypt(key: key, nonce: nonce, initialSeq: 0)
        var bad = [UInt8](hex: "7680ea16798357df88b11466330e24d3f200b0e6")!
        bad[0] ^= 1
        XCTAssertThrowsError(try rx.decrypt(bad))
        XCTAssertEqual(rx.rxSeq, 0)
    }

    func testKeyDatabaseRejectsCorruption() throws {
        var bytes = [UInt8](hex: "f75995e7040101" + String(repeating: "00", count: 80))!
        XCTAssertThrowsError(try KeyDatabase(bytes: bytes)) { XCTAssertEqual($0 as? KeyDatabaseError, .crcMismatch) }
        bytes.removeLast()
        XCTAssertThrowsError(try KeyDatabase(bytes: bytes))
    }

    func testServerReproducesCapturedPumpHandshake() throws {
        let db = try loadPumpKeyDatabase()
        XCTAssertEqual(db.localDeviceType, .mobileApplication)
        let random = QueuedRandom([
            Array(pumpTrace[0][2..<20]),
            Array(pumpTrace[2][8..<16]),
            Array(pumpTrace[2][16..<20]),
        ])
        let server = SakeServer(keyDatabase: db, random: random)
        server.msg4Pad = 0xF7 // pad byte of the captured trace (JavaSake SakeServerTest)

        XCTAssertEqual(try server.handle([UInt8](repeating: 0, count: 20)), pumpTrace[0])
        XCTAssertEqual(try server.handle(pumpTrace[1]), pumpTrace[2])
        XCTAssertEqual(try server.handle(pumpTrace[3]), pumpTrace[4])
        XCTAssertNil(try server.handle(pumpTrace[5]))
        XCTAssertTrue(server.isComplete)
        XCTAssertEqual(server.crypt?.txSeq, 3)
        XCTAssertEqual(server.crypt?.rxSeq, 2)
    }

    func testServerRejectsForgedClientAuth() throws {
        let db = try loadPumpKeyDatabase()
        let server = SakeServer(keyDatabase: db)
        _ = try server.handle([UInt8](repeating: 0, count: 20))
        _ = try server.handle(pumpTrace[1])
        // msg3 from the trace does not match our fresh random key material.
        XCTAssertThrowsError(try server.handle(pumpTrace[3]))
        XCTAssertFalse(server.isComplete)
    }

    func testServerRejectsNonZeroStart() throws {
        let db = try loadPumpKeyDatabase()
        let server = SakeServer(keyDatabase: db)
        XCTAssertThrowsError(try server.handle(pumpTrace[1]))
        XCTAssertThrowsError(try server.handle([0x00]))
    }
}

final class SeqCryptStateTests: XCTestCase {
    func testStateRoundTrip() throws {
        let key = [UInt8](hex: "00112233445566778899aabbccddeeff")!
        let nonce = [UInt8](hex: "a1b2c3d4e5f60718")!
        let a = SeqCrypt(key: key, nonce: nonce, initialSeq: 1)
        _ = try a.encrypt([1, 2, 3])
        let data = try JSONEncoder().encode(a.state)
        let b = try XCTUnwrap(SeqCrypt(state: try JSONDecoder().decode(SeqCrypt.State.self, from: data)))
        XCTAssertEqual(b.txSeq, 3)
        XCTAssertEqual(try a.encrypt([4]), try b.encrypt([4]))
    }
}
