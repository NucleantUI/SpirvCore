// swift-tools-version: 6.1

import PackageDescription

let package = Package(
    name: "SpirvCore",
    platforms: [
        .macOS(.v14),
        .iOS(.v17),
    ],
    products: [
        .library(
            name: "SpirvCore",
            targets: ["SpirvCore"]
        ),
    ],
    targets: [
        // The SPIR-V opcode tables, instruction encoding and a word-stream
        // reader, shared by anything that writes or reads a SPIR-V module.
        .target(
            name: "SpirvCore"
        ),
        .testTarget(
            name: "SpirvCoreTests",
            dependencies: ["SpirvCore"]
        ),
    ],
    swiftLanguageModes: [.v6]
)
