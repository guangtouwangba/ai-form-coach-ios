// swift-tools-version: 6.2
import PackageDescription
let package = Package(
    name: "CoachQwenPreflight",
    platforms: [.macOS(.v14), .iOS(.v17)],
    products: [
        .library(name: "CoachQwenPreflight", targets: ["CoachQwenPreflight"]),
        .executable(name: "CoachConfigAudit", targets: ["CoachConfigAudit"]),
        .executable(name: "CoachVideoBenchmark", targets: ["CoachVideoBenchmark"])
    ],
    dependencies: [
        .package(url: "https://github.com/ml-explore/mlx-swift-lm", exact: "3.32.3", traits: []),
        .package(url: "https://github.com/ml-explore/mlx-swift", exact: "0.32.3"),
        .package(url: "https://github.com/huggingface/swift-transformers", exact: "1.3.0"),
        .package(url: "https://github.com/huggingface/swift-huggingface", exact: "0.9.0")
    ],
    targets: [
        .target(name: "CoachQwenPreflight", dependencies: [
            .product(name: "MLXVLM", package: "mlx-swift-lm"),
            .product(name: "MLXLMCommon", package: "mlx-swift-lm"),
            .product(name: "HuggingFace", package: "swift-huggingface"),
            .product(name: "Tokenizers", package: "swift-transformers")
        ]),
        .executableTarget(name: "CoachConfigAudit", dependencies: [
            "CoachQwenPreflight",
            .product(name: "Tokenizers", package: "swift-transformers")
        ]),
        .executableTarget(name: "CoachVideoBenchmark", dependencies: [
            "CoachQwenPreflight",
            .product(name: "MLX", package: "mlx-swift"),
            .product(name: "MLXVLM", package: "mlx-swift-lm"),
            .product(name: "MLXLMCommon", package: "mlx-swift-lm")
        ])
    ]
)
