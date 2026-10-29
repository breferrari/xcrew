// swift-tools-version:6.2
import PackageDescription

// macOS 26 because Xcode 27, which the Xcode MCP needs, requires it.
// No dependencies on purpose: bin/xcrew builds this on first use, and a dependency-free
// package builds in seconds with nothing to resolve or download.
/// Language features each Swift target opts into: upcoming defaults adopted early, and memory
/// safety checked. Warnings are errors only in CI (`-warnings-as-errors`), never here: a newer
/// Swift adding a warning must not break someone's first build.
let swiftSettings: [SwiftSetting] = [
    .enableUpcomingFeature("ExistentialAny"),
    .enableUpcomingFeature("MemberImportVisibility"),
    .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
    .enableUpcomingFeature("InferIsolatedConformances"),
    .strictMemorySafety(),
]

let package = Package(
    name: "xcrew",
    platforms: [.macOS(.v26)],
    products: [
        .executable(name: "xcrew", targets: ["xcrew"]),
    ],
    targets: [
        .target(name: "XcrewCore", swiftSettings: swiftSettings),
        .target(name: "XcrewCLI", dependencies: ["XcrewCore"], swiftSettings: swiftSettings),
        .executableTarget(name: "xcrew", dependencies: ["XcrewCLI"], swiftSettings: swiftSettings),
        .target(name: "XcrewTestSupport", dependencies: ["XcrewCore"], path: "Tests/XcrewTestSupport", swiftSettings: swiftSettings),
        .testTarget(
            name: "XcrewCoreTests",
            dependencies: ["XcrewCore", "XcrewTestSupport"],
            resources: [.copy("Fixtures")],
            swiftSettings: swiftSettings
        ),
        .testTarget(name: "ShimTests", swiftSettings: swiftSettings),
        .testTarget(name: "ManifestTests", dependencies: ["XcrewCLI", "XcrewCore"], swiftSettings: swiftSettings),
        .testTarget(name: "XcrewCLITests", dependencies: ["XcrewCLI", "XcrewCore", "XcrewTestSupport"], swiftSettings: swiftSettings),
    ]
)
