// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "AIFormCoach",
    platforms: [.macOS(.v14), .iOS(.v17)],
    products: [
        .library(name: "FormCoachCore", targets: ["FormCoachCore"])
    ],
    targets: [
        .target(name: "FormCoachCore"),
        .testTarget(name: "FormCoachCoreTests", dependencies: ["FormCoachCore"])
    ]
)
