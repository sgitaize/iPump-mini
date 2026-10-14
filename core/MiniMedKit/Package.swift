// swift-tools-version: 6.0
// MiniMedKit – read-only protocol library for MiniMed 700-series pumps.
// SPDX-License-Identifier: GPL-3.0-or-later
import PackageDescription

let package = Package(
    name: "MiniMedKit",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "MiniMedKit", targets: ["MiniMedKit"]),
    ],
    targets: [
        .target(name: "MiniMedKit"),
        .testTarget(name: "MiniMedKitTests", dependencies: ["MiniMedKit"]),
    ]
)
