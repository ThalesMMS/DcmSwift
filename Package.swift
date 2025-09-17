// swift-tools-version:5.7
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "DcmSwift",
    platforms: [
        .macOS(.v10_15),
        .iOS(.v13)
    ],
    products: [
        // Products define the executables and libraries produced by a package, and make them visible to other packages.
        .library(
            name: "DcmSwift",
            targets: ["DcmSwift"]),
        .executable(name: "DcmAnonymize", targets: ["DcmAnonymize"]),
        .executable(name: "DcmPrint", targets: ["DcmPrint"]),
        .executable(name: "DcmServer", targets: ["DcmServer"]),
        .executable(name: "DcmEcho", targets: ["DcmEcho"]),
        .executable(name: "DcmStore", targets: ["DcmStore"]),
        .executable(name: "DcmSR", targets: ["DcmSR"]),
        .executable(name: "DcmGet", targets: ["DcmGet"]),
        .executable(name: "DcmMove", targets: ["DcmMove"]),
        .executable(name: "DcmDecompress", targets: ["DcmDecompress"])
    ],
    dependencies: [
        // Dependencies declare other packages that this package depends on.
        .package(name: "Socket", url: "https://github.com/Kitura/BlueSocket.git", from:"1.0.8"),
        .package(url: "https://github.com/apple/swift-argument-parser", from: "0.4.0"),
        .package(url: "https://github.com/pointfreeco/swift-html", from: "0.4.0"),
        .package(url: "https://github.com/apple/swift-nio.git", from: "2.40.0"),
        .package(url: "https://github.com/apple/swift-nio-ssl.git", from: "2.17.0")
    ],
    targets: [
        // Targets are the basic building blocks of a package. A target can define a module or a test suite.
        // Targets can depend on other targets in this package, and on products in packages which this package depends on.
        
        .target(
            name: "DcmSwift",
            dependencies: [ 
                "Socket", 
                .product(name: "NIO", package: "swift-nio"), 
                .product(name: "NIOSSL", package: "swift-nio-ssl"),
                .product(name: "Html", package: "swift-html"),
                "OpenJPH"
            ],
            resources: [
                // Resources are specified relative to the target directory
                .process("Graphics/Shaders.metal")
            ]
        ),
        .target(
            name: "OpenJPH",
            dependencies: [],
            path: "Sources/OpenJPH",
            publicHeadersPath: "include",
            cxxSettings: [
                .headerSearchPath("core"),
                .headerSearchPath("core/common"),
                .headerSearchPath("core/others"),
                .headerSearchPath("core/codestream"),
                .headerSearchPath("core/coding"),
                .headerSearchPath("core/transform"),
                .define("OJPH_DISABLE_TIFF_SUPPORT", to: "1"),
                .define("OJPH_DISABLE_TIFF", to: "1"),
                .define("OJPH_DISABLE_WASM_SIMD", to: "1"),
                .unsafeFlags(["-std=c++17"], .when(platforms: [.macOS, .iOS]))
            ]
        ),
        .executableTarget(
            name: "DcmAnonymize",
            dependencies: [
                "DcmSwift",
                .product(name: "ArgumentParser", package: "swift-argument-parser")
            ]),
        .executableTarget(
            name: "DcmPrint",
            dependencies: [
                "DcmSwift",
                .product(name: "ArgumentParser", package: "swift-argument-parser")
            ]),
        .executableTarget(
            name: "DcmSR",
            dependencies: [
                "DcmSwift",
                .product(name: "ArgumentParser", package: "swift-argument-parser")
            ]),
        .executableTarget(
            name: "DcmServer",
            dependencies: [
                "DcmSwift",
                .product(name: "ArgumentParser", package: "swift-argument-parser")
            ]),
        .executableTarget(
            name: "DcmEcho",
            dependencies: [
                "DcmSwift",
                .product(name: "ArgumentParser", package: "swift-argument-parser")
            ]),
        .executableTarget(
            name: "DcmStore",
            dependencies: [
                "DcmSwift",
                .product(name: "ArgumentParser", package: "swift-argument-parser")
            ]),
        .executableTarget(
            name: "DcmFind",
            dependencies: [
                "DcmSwift",
                .product(name: "ArgumentParser", package: "swift-argument-parser")
            ]),
        .executableTarget(
            name: "DcmGet",
            dependencies: [
                "DcmSwift",
                .product(name: "ArgumentParser", package: "swift-argument-parser")
            ]),
        .executableTarget(
            name: "DcmMove",
            dependencies: [
                "DcmSwift",
                .product(name: "ArgumentParser", package: "swift-argument-parser")
            ]),
        .executableTarget(
            name: "DcmDecompress",
            dependencies: [
                "DcmSwift"
            ]),
        .testTarget(
            name: "DcmSwiftTests",
            dependencies: ["DcmSwift"],
            resources: [
                .process("../DICOM_Test")
            ]
        )
    ]
)
