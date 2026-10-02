// swift-tools-version:5.9
// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint
// Copyright (C) 2026 Hussaini Holding

import PackageDescription

let package = Package(
    name: "Rukn",
    platforms: [.macOS(.v14)],
    targets: [
        .systemLibrary(
            name: "HIDEventSystem",
            path: "Sources/HIDEventSystem"
        ),
        .systemLibrary(
            name: "VMStatisticsCompat",
            path: "Sources/VMStatisticsCompat"
        ),
        .executableTarget(
            name: "Rukn",
            dependencies: ["VMStatisticsCompat", "HIDEventSystem"],
            path: "Sources/Rukn"
        )
    ]
)
