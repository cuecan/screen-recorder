// swift-tools-version: 6.2
import PackageDescription

/// Everything the app and the `cuecan` CLI share. The app and the MCP server are thin front ends on these
/// modules, and both read and write the same project folder (docs/architecture.md).
let package = Package(
    name: "CueCanKit",
    // macOS 26 for Apple's SpeechAnalyzer and SpeechDetector (docs/decisions.md, 27).
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "ProjectKit", targets: ["ProjectKit"]),
        .library(name: "RecorderKit", targets: ["RecorderKit"]),
        .library(name: "AudioKit", targets: ["AudioKit"]),
        .library(name: "TranscribeKit", targets: ["TranscribeKit"]),
        .library(name: "RenderKit", targets: ["RenderKit"]),
        .library(name: "ProcessingKit", targets: ["ProcessingKit"]),
        .library(name: "UpdateKit", targets: ["UpdateKit"]),
        .executable(name: "cuecan", targets: ["cuecan"]),
    ],
    dependencies: [
        // Parakeet TDT on Core ML: the primary transcript (docs/decisions.md, 39). FluidAudio has no
        // dependencies of its own. Only the NemoTextProcessing trait, which leaves out its text-to-speech
        // and diarization. That trait is needed: in 0.18.2, with no traits, its speech-to-text code still
        // calls the text-normalization library and the build fails to link.
        .package(url: "https://github.com/FluidInference/FluidAudio", exact: "0.18.2", traits: ["NemoTextProcessing"]),
        // The official MCP SDK, for `cuecan mcp`: a stdio server with image results (docs/design.md,
        // "The MCP server").
        .package(url: "https://github.com/modelcontextprotocol/swift-sdk", from: "0.12.1"),
        // Check for Updates… in the app (docs/decisions.md, 91). Only UpdateKit uses it, so the CLI never
        // links it.
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.10.1"),
    ],
    targets: [
        .target(name: "ProjectKit"),
        .target(name: "RecorderKit", dependencies: ["ProjectKit"]),
        // Cleanup is Apple's AUSoundIsolation; Voice and Loudness are our own DSP. No dependencies.
        // Optimized in Debug too: its per-sample loops run about 80 times slower unoptimized, which made
        // normalized playback in Xcode's copy of the app take longer than the take (measured).
        .target(
            name: "AudioKit",
            dependencies: ["ProjectKit"],
            swiftSettings: [.unsafeFlags(["-O"], .when(configuration: .debug))]
        ),
        .target(
            name: "TranscribeKit",
            dependencies: [
                "ProjectKit",
                "AudioKit",
                .product(name: "FluidAudio", package: "FluidAudio"),
            ]
        ),
        .target(name: "RenderKit", dependencies: ["ProjectKit"]),
        // What runs on its own after a recording: transcribing, and cleaning each mic source
        // into `audio/`. It sits on top of AudioKit and TranscribeKit, so neither depends on the other for it.
        .target(name: "ProcessingKit", dependencies: ["ProjectKit", "AudioKit", "TranscribeKit"]),
        // The app's updater, a thin layer on Sparkle. It depends on nothing else here.
        .target(name: "UpdateKit", dependencies: [.product(name: "Sparkle", package: "Sparkle")]),
        .executableTarget(
            name: "cuecan",
            dependencies: [
                "ProjectKit", "AudioKit", "TranscribeKit", "RenderKit", "ProcessingKit",
                .product(name: "MCP", package: "swift-sdk"),
            ]
        ),
        .testTarget(name: "ProjectKitTests", dependencies: ["ProjectKit"]),
        .testTarget(name: "AudioKitTests", dependencies: ["AudioKit"]),
        .testTarget(name: "TranscribeKitTests", dependencies: ["TranscribeKit", "ProjectKit", "AudioKit"]),
        .testTarget(name: "RenderKitTests", dependencies: ["RenderKit", "ProjectKit", "AudioKit"]),
        .testTarget(name: "RecorderKitTests", dependencies: ["RecorderKit", "ProjectKit"]),
        .testTarget(name: "ProcessingKitTests", dependencies: ["ProcessingKit", "ProjectKit"]),
        .testTarget(name: "CuecanTests", dependencies: ["cuecan", "ProjectKit", "RenderKit"]),
    ]
)
