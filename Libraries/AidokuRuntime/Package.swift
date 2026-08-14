// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "AidokuRuntime",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "AidokuRuntime", targets: ["AidokuRuntime"]),
    ],
    dependencies: [
        .package(
            url: "https://github.com/scinfu/SwiftSoup.git",
            exact: "2.13.7"
        ),
        .package(
            url: "https://github.com/weichsel/ZIPFoundation.git",
            exact: "0.9.20"
        ),
    ],
    targets: [
        .target(
            name: "AidokuRuntime",
            dependencies: ["Wasm3", "SwiftSoup", "ZIPFoundation", "AidokuRuntimeWatchdog"]
        ),
        .target(
            name: "Wasm3",
            dependencies: ["wasm3-c", "wasm3-support"]
        ),
        .target(
            name: "wasm3-c",
            cSettings: [
                .define("APPLICATION_EXTENSION_API_ONLY", to: "YES"),
                .define("d_m3MaxDuplicateFunctionImpl", to: "10"),
                .define("d_m3HasWASI", to: "YES"),
                .unsafeFlags(["-Wno-shorten-64-to-32"]),
                // Wasm3 is an interpreter. Leaving its dispatch loop at -O0 in
                // Debug makes large-but-valid source responses exceed the same
                // metadata watchdog used by Release builds.
                .unsafeFlags(["-O2"], .when(configuration: .debug)),
            ]
        ),
        .target(
            name: "wasm3-support",
            dependencies: ["wasm3-c"]
        ),
        .target(
            name: "AidokuRuntimeWatchdog",
            dependencies: [],
            publicHeadersPath: "include"
        ),
        .testTarget(
            name: "AidokuRuntimeTests",
            dependencies: ["AidokuRuntime", "SwiftSoup", "ZIPFoundation"]
        ),
    ],
    swiftLanguageModes: [.v6]
)
