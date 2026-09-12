// swift-tools-version: 6.0
import PackageDescription
import Foundation

// Extraction flags apply only to our app target, never to dependency builds.
let environment = ProcessInfo.processInfo.environment
var intentSettings: [SwiftSetting] = []
if let protocols = environment["VOICE_INTENT_PROTOCOLS"], let output = environment["VOICE_INTENT_VALUES"] {
    intentSettings = [.unsafeFlags(["-Xfrontend", "-const-gather-protocols-file", "-Xfrontend", protocols,
                                   "-emit-const-values-path", output])]
}

let package = Package(
    name: "Workbench",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "LocalVoice", targets: ["LocalVoice"])],
    dependencies: [.package(url: "https://github.com/FluidInference/FluidAudio.git", exact: "0.15.6")],
    targets: [
        .target(name: "StageKit", linkerSettings: [.linkedFramework("Carbon")]),
        .executableTarget(name: "LocalVoice", dependencies: ["StageKit", .product(name: "FluidAudio", package: "FluidAudio")], swiftSettings: intentSettings, linkerSettings: [.linkedFramework("Carbon")])
    ],
    swiftLanguageModes: [.v5]
)
