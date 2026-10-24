// swift-tools-version: 5.9
import PackageDescription

// capgo-visionkit-swizzle: scripts/configure-visionkit-swizzle.mjs sets this during cap sync.
// false keeps the private VisionKit swizzle out of the App Store binary.
let visionKitSwizzleEnabled = false

let package = Package(
    name: "CapgoCapacitorDocumentScanner",
    platforms: [.iOS(.v15)],
    products: [
        .library(
            name: "CapgoCapacitorDocumentScanner",
            targets: ["DocumentScannerPlugin"])
    ],
    dependencies: [
        .package(url: "https://github.com/ionic-team/capacitor-swift-pm.git", from: "8.0.0")
    ],
    targets: [
        .target(
            name: "DocumentScannerPlugin",
            dependencies: [
                .product(name: "Capacitor", package: "capacitor-swift-pm"),
                .product(name: "Cordova", package: "capacitor-swift-pm")
            ],
            path: "ios/Sources/DocumentScannerPlugin",
            swiftSettings: visionKitSwizzleEnabled
                ? [.define("CAPGO_DOCUMENT_SCANNER_VISIONKIT_SWIZZLE")]
                : []),
        .testTarget(
            name: "DocumentScannerPluginTests",
            dependencies: ["DocumentScannerPlugin"],
            path: "ios/Tests/DocumentScannerPluginTests")
    ]
)
