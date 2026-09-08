// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "LocalVoice",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "LocalVoice", targets: ["LocalVoice"])],
    dependencies: [.package(url: "https://github.com/FluidInference/FluidAudio.git", exact: "0.15.6")],
    targets: [
        .executableTarget(name: "LocalVoice", dependencies: [.product(name: "FluidAudio", package: "FluidAudio")])
    ],
    swiftLanguageModes: [.v5]
)
