// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "MaxVoice",
    platforms: [.macOS(.v13)],
    dependencies: [
        .package(url: "https://github.com/grpc/grpc-swift.git", from: "1.24.0"),
        .package(url: "https://github.com/apple/swift-protobuf.git", from: "1.25.0"),
    ],
    targets: [
        .executableTarget(
            name: "MaxVoice",
            dependencies: [
                .product(name: "GRPC", package: "grpc-swift"),
                .product(name: "SwiftProtobuf", package: "swift-protobuf"),
            ],
            path: "MaxVoice",
            exclude: ["Info.plist"]
        ),
    ]
)
