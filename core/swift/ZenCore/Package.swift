// swift-tools-version: 6.0
// The Swift face of libzen_core: UniFFI-generated bindings for every Rust
// component, as one `ZenCore` module the app imports on iOS and Android.
//
// Sources/ZenCore/Generated and Sources/ZenCoreFFI/include are produced by
// scripts/generate-swift-bindings.sh.
//
// Linking:
// - Apple: ZenCoreRust.xcframework (scripts/build-core-ios.sh), a static lib.
// - Android: lib/android/<abi>/libzen_core.so (scripts/build-core-android.sh).
//   SwiftPM can't vary linker flags by architecture, so a build covers one
//   ABI: arm64-v8a (phones, Apple silicon emulators) unless ZEN_ANDROID_ABI
//   says otherwise (x86_64 for the CI emulator).
// - Linux (tests): pass the library's directory with `-Xlinker -L<dir>`
//   (see scripts/test-swift-linux.sh).
import Foundation
import PackageDescription

let packageDir = URL(fileURLWithPath: #filePath).deletingLastPathComponent().path
let androidABI = Context.environment["ZEN_ANDROID_ABI"] ?? "arm64-v8a"

var zenCoreDependencies: [Target.Dependency] = ["ZenCoreFFI"]
var extraTargets: [Target] = []

#if os(macOS)
zenCoreDependencies.append(.target(name: "ZenCoreRust", condition: .when(platforms: [.iOS, .macOS])))
extraTargets.append(.binaryTarget(name: "ZenCoreRust", path: "ZenCoreRust.xcframework"))
#endif

let package = Package(
    name: "ZenCore",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "ZenCore", targets: ["ZenCore"]),
    ],
    targets: [
        .target(name: "ZenCoreFFI"),
        .target(
            name: "ZenCore",
            dependencies: zenCoreDependencies,
            swiftSettings: [
                // UniFFI's generated Swift predates strict concurrency checking.
                .swiftLanguageMode(.v5),
            ],
            linkerSettings: [
                .linkedLibrary("zen_core", .when(platforms: [.linux, .android])),
                .unsafeFlags(["-L\(packageDir)/lib/android/\(androidABI)"], .when(platforms: [.android])),
                // What the Rust static library needs from the system on iOS.
                .linkedLibrary("c++", .when(platforms: [.iOS, .macOS])),
                .linkedFramework("Security", .when(platforms: [.iOS, .macOS])),
                .linkedFramework("SystemConfiguration", .when(platforms: [.iOS, .macOS])),
            ]
        ),
        .testTarget(
            name: "ZenCoreTests",
            dependencies: ["ZenCore"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ] + extraTargets
)
