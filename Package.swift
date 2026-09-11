// swift-tools-version:5.9

import PackageDescription

let package = Package(
    name: "Write",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "Write", targets: ["Write"]),
        .library(name: "WriteKit", targets: ["WriteKit"]),
    ],
    targets: [
        // Pure Foundation logic: Markdown scanning, word counting, link and
        // file-name normalization. Kept free of AppKit so it can be unit
        // tested without a running window server.
        .target(name: "WriteKit"),
        .executableTarget(name: "Write", dependencies: ["WriteKit"]),
        .testTarget(name: "WriteKitTests", dependencies: ["WriteKit"]),
        // AppKit-level tests: the highlighter against a real NSTextStorage.
        .testTarget(name: "WriteTests", dependencies: ["Write"]),
    ]
)
