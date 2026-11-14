// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Wallpaper",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(
            name: "WallpaperCore",
            targets: ["WallpaperCore"]
        ),
        .executable(
            name: "WallpaperApp",
            targets: ["WallpaperApp"]
        )
    ],
    dependencies: [],
    targets: [
        // Core business logic, rendering engines, power monitoring, and UI components
        .target(
            name: "WallpaperCore",
            dependencies: [],
            path: "Sources/WallpaperCore"
        ),
        // Standalone executable target for the macOS accessory app
        .executableTarget(
            name: "WallpaperApp",
            dependencies: [
                "WallpaperCore"
            ],
            path: "Sources/WallpaperApp"
        ),
        // Unit test suite for models, parsers, engines, and managers
        .testTarget(
            name: "WallpaperCoreTests",
            dependencies: [
                "WallpaperCore"
            ],
            path: "Tests/WallpaperCoreTests"
        ),
        // Opaque-box E2E test harness covering Tiers 1 to 4
        .testTarget(
            name: "WallpaperE2ETests",
            dependencies: [
                "WallpaperCore"
            ],
            path: "Tests/WallpaperE2ETests"
        )
    ],
    swiftLanguageModes: [.v6]
)
