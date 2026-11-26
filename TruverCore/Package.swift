// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "TruverCore",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "TruverTheory", targets: ["TruverTheory"]),
        .library(name: "TruverDSP", targets: ["TruverDSP"]),
        .library(name: "TruverAudio", targets: ["TruverAudio"]),
        // Platform-neutral audio host (AAudio on Android, WASAPI on Windows later).
        .library(name: "TruverHost", targets: ["TruverHost"]),
        // C API for the Flutter app (Android, Windows): libTruverBridge.so / TruverBridge.dll.
        .library(name: "TruverBridge", type: .dynamic, targets: ["TruverBridge"]),
    ],
    targets: [
        // Pure music theory and instrument logic: no UI, no audio, no persistence (PRD 5.1, 5.2, 5.5, TU-6).
        .target(name: "TruverTheory"),
        // Pure signal processing and timing: pitch tracking (TU-1…TU-8) and the metronome clock (ME-1…ME-12).
        // Works on sample buffers only, so it is tested with synthetic signals.
        .target(name: "TruverDSP", dependencies: ["TruverTheory", "TruverAtomics"]),
        // C11 atomics for lock-free real-time queues (no Swift Atomic type before iOS 18).
        .target(name: "TruverAtomics"),
        // Thin AVFoundation layer: audio session (AU-1, AU-3, AU-5), engine, metronome output, microphone input.
        .target(name: "TruverAudio", dependencies: ["TruverTheory", "TruverDSP"]),
        // AAudio helpers (Android only; empty elsewhere).
        .target(name: "CTruverAndroid",
                linkerSettings: [.linkedLibrary("aaudio", .when(platforms: [.android])),
                                 .linkedLibrary("log", .when(platforms: [.android]))]),
        // Metronome, synth and tuner on top of a platform audio backend — the Android/Windows twin of TruverAudio.
        .target(name: "TruverHost", dependencies: ["TruverTheory", "TruverDSP", "TruverAtomics",
                                                   .target(name: "CTruverAndroid", condition: .when(platforms: [.android]))]),
        // JSON-over-C bridge for dart:ffi.
        .target(name: "TruverBridge", dependencies: ["TruverHost", "TruverTheory", "TruverDSP"]),
        .testTarget(name: "TruverTheoryTests", dependencies: ["TruverTheory"]),
        .testTarget(name: "TruverDSPTests", dependencies: ["TruverDSP", "TruverTheory"]),
        .testTarget(name: "TruverAudioTests", dependencies: ["TruverAudio", "TruverDSP"]),
    ]
)
