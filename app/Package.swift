// swift-tools-version: 6.1
// This is a Skip (https://skip.dev) package.
import PackageDescription

let package = Package(
    name: "zen-mobile",
    defaultLocalization: "en",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "ZenMobile", type: .dynamic, targets: ["ZenMobile"]),
    ],
    dependencies: [
        .package(url: "https://github.com/skiptools/skip.git", from: "1.9.20"),
        .package(url: "https://github.com/skiptools/skip-fuse-ui.git", from: "1.0.0"),
        // Keychain on iOS, encrypted preferences on Android: holds the
        // Firefox account.
        .package(url: "https://github.com/skiptools/skip-keychain.git", from: "0.3.4"),
        // The Rust core's Swift bindings. Run scripts/generate-swift-bindings.sh
        // and scripts/build-core-{ios,android}.sh first.
        .package(path: "../core/swift/ZenCore"),
    ],
    targets: [
        .target(name: "ZenMobile", dependencies: [
            .product(name: "SkipFuseUI", package: "skip-fuse-ui"),
            .product(name: "SkipKeychain", package: "skip-keychain"),
            .product(name: "ZenCore", package: "ZenCore"),
        ], resources: [.process("Resources")], plugins: [.plugin(name: "skipstone", package: "skip")]),
    ]
)
