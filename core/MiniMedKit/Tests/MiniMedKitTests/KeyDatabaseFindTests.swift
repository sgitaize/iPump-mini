// SPDX-License-Identifier: GPL-3.0-or-later
import XCTest
@testable import MiniMedKit

final class KeyDatabaseFindTests: XCTestCase {
    private let isMobilePump: (KeyDatabase) -> Bool = {
        $0.localDeviceType == .mobileApplication && $0.remoteDevices[.insulinPump] != nil
    }

    func testIgnoresNonHexAndGarbage() {
        XCTAssertNil(KeyDatabase.findHex(in: "<code>0x0001dcf0</code> hello", accept: { _ in true }))
        XCTAssertNil(KeyDatabase.findHex(in: "", accept: { _ in true }))
    }

    /// The published page (copy in the gitignored _vendor/keys/) contains an address block,
    /// the pump database, a sensor database and a development database. The pump database
    /// must be picked and must equal the local one.
    func testFindsPumpDatabaseOnOpenMinimedPage() throws {
        let repo = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        guard let page = try? String(contentsOf: repo.appendingPathComponent("_vendor/keys/key_databases.md"), encoding: .utf8),
              let local = try? String(contentsOf: repo.appendingPathComponent("_vendor/keys/mobile-pump.keydb.hex"), encoding: .utf8)
        else { throw XCTSkip("_vendor/keys/key_databases.md oder mobile-pump.keydb.hex fehlt") }
        let found = KeyDatabase.findHex(in: page, accept: isMobilePump)
        XCTAssertEqual(found?.lowercased(), local.filter { !$0.isWhitespace }.lowercased())
        // Plain hex with spaces and line breaks works too.
        XCTAssertNotNil(KeyDatabase.findHex(in: local.replacingOccurrences(of: "0", with: "0 "), accept: isMobilePump))
    }
}
