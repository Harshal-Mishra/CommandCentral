// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "CommandCentral",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/migueldeicaza/SwiftTerm.git", from: "1.2.0"),
    ],
    targets: [
        .executableTarget(
            name: "CommandCentral",
            dependencies: [
                .product(name: "SwiftTerm", package: "SwiftTerm"),
            ],
            path: "Sources/CommandCentral"
        )
    ]
)
