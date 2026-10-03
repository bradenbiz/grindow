// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "GrindowCore",
    platforms: [.macOS(.v13)],
    products: [.library(name: "GrindowCore", targets: ["GrindowCore"])],
    targets: [
        .target(name: "GrindowCore", path: "Grindow", exclude: [
            "AppDelegate.swift", "GrindowApp.swift", "Views", "Vendor", "Assets.xcassets",
            "Info.plist", "Grindow.entitlements", "Grindow-Bridging-Header.h",
            "Services/SpaceManager.swift", "Services/GestureInterceptor.swift", "Services/AccessibilityHelper.swift"
        ], sources: ["Models", "Services/SpaceSwitchCoordinator.swift"]),
        .testTarget(name: "GrindowCoreTests", dependencies: ["GrindowCore"], path: "Tests", exclude: ["Native"])
    ]
)
