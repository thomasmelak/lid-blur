// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "LidBlur",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "LidBlur", targets: ["LidBlur"]),
    ],
    targets: [
        .target(name: "LidBlurCore"),
        .executableTarget(
            name: "LidBlur",
            dependencies: ["LidBlurCore"],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("IOKit"),
                .linkedFramework("ScreenCaptureKit"),
            ]
        ),
        .testTarget(name: "LidBlurCoreTests", dependencies: ["LidBlurCore"]),
    ]
)
