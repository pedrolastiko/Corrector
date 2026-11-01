// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Corrector",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "CorrectorDelta", targets: ["CorrectorDelta"]),
        .library(name: "CorrectorCore", targets: ["CorrectorCore"]),
        .library(name: "CorrectorEngine", targets: ["CorrectorEngine"]),
        .library(name: "CorrectorSession", targets: ["CorrectorSession"]),
        .library(name: "CorrectorAppCore", targets: ["CorrectorAppCore"]),
        .executable(name: "corrector", targets: ["corrector"]),
        .executable(name: "CorrectorApp", targets: ["CorrectorApp"]),
    ],
    targets: [
        .target(name: "CorrectorDelta", swiftSettings: [.swiftLanguageMode(.v5)]),
        .target(name: "CorrectorCore", dependencies: ["CorrectorDelta"], swiftSettings: [.swiftLanguageMode(.v5)]),
        .target(name: "CorrectorEngine", dependencies: ["CorrectorCore", "CorrectorDelta"], swiftSettings: [.swiftLanguageMode(.v5)]),
        .target(name: "CorrectorSession", dependencies: ["CorrectorCore", "CorrectorEngine", "CorrectorDelta"], swiftSettings: [.swiftLanguageMode(.v5)]),
        .executableTarget(name: "corrector",
                          dependencies: ["CorrectorCore", "CorrectorEngine", "CorrectorSession", "CorrectorDelta"],
                          resources: [.copy("Samples")],
                          swiftSettings: [.swiftLanguageMode(.v5)]),
        // Everything the applications do that is not a view.
        //
        // CorrectorApp is an executable, and nothing can import an executable,
        // so for as long as this logic lived there it could not be tested at
        // all — which is exactly where every defect found by hand this cycle
        // turned out to be.
        .target(name: "CorrectorAppCore",
                dependencies: ["CorrectorCore", "CorrectorEngine",
                               "CorrectorSession", "CorrectorDelta"],
                swiftSettings: [.swiftLanguageMode(.v5)]),
        .executableTarget(name: "CorrectorApp",
                          dependencies: ["CorrectorAppCore", "CorrectorCore",
                                         "CorrectorEngine", "CorrectorSession",
                                         "CorrectorDelta"],
                          swiftSettings: [.swiftLanguageMode(.v5)]),
        .testTarget(name: "CorrectorDeltaTests", dependencies: ["CorrectorDelta"], swiftSettings: [.swiftLanguageMode(.v5)]),
        .testTarget(name: "CorrectorCoreTests", dependencies: ["CorrectorCore"], swiftSettings: [.swiftLanguageMode(.v5)]),
        .testTarget(name: "CorrectorEngineTests", dependencies: ["CorrectorEngine"], swiftSettings: [.swiftLanguageMode(.v5)]),
        .testTarget(name: "CorrectorSessionTests", dependencies: ["CorrectorSession"], swiftSettings: [.swiftLanguageMode(.v5)]),
        .testTarget(name: "CorrectorAppCoreTests",
                    dependencies: ["CorrectorAppCore", "CorrectorCore",
                                   "CorrectorEngine", "CorrectorSession"],
                    swiftSettings: [.swiftLanguageMode(.v5)]),
    ]
)
