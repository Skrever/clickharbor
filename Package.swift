// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "AiroxUtility",
    platforms: [.macOS(.v14)],
    targets: [
        .target(
            name: "CHID",
            linkerSettings: [.linkedFramework("IOKit"), .linkedFramework("CoreFoundation")]
        ),
        .executableTarget(name: "AiroxUtility", dependencies: ["CHID"]),
        .testTarget(name: "AiroxUtilityTests", dependencies: ["AiroxUtility"])
    ]
)
