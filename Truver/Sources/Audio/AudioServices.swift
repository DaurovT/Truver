import AVFoundation
import TruverAudio
import TruverDSP
import TruverTheory

enum MicPermission: Equatable {
    /// `restricted`: a profile or parental controls forbid the microphone — the user cannot allow it (canvas
    /// «Тюнер — доступ ограничен»).
    case undetermined, granted, denied, restricted
}

/// Audio policy of the app: one engine, the session category switched only at module start/stop (AU-5),
/// microphone only while a module needs it (AU-4).
@MainActor
final class AudioServices {
    let host = AudioEngineHost()
    #if os(iOS)
    let session = AudioSessionController()
    #endif

    var onConfigurationChange: (() -> Void)?

    /// ME-9: manual corrections in ms per output name, from the settings.
    var latencyOffsets: [String: Double] = [:] { didSet { applyLatency() } }

    /// Output name the correction is stored under.
    var outputName: String {
        #if os(iOS)
        return session.currentOutputName ?? "Динамик"
        #else
        return "Выход"
        #endif
    }

    /// Latency the system reports for the current output, seconds.
    var systemOutputLatency: TimeInterval {
        #if os(iOS)
        return session.outputLatency
        #else
        return host.engine.outputNode.presentationLatency
        #endif
    }

    /// The beat timeline and the flash use system latency + manual correction (ME-9, ME-12).
    func applyLatency() {
        let manual = (latencyOffsets[outputName] ?? 0) / 1000
        host.outputLatency = max(0, systemOutputLatency + manual)
    }

    init() {
        host.onConfigurationChange = { [weak self] in
            MainActor.assumeIsolated { self?.onConfigurationChange?() }
        }
    }

    var micPermission: MicPermission {
        #if os(iOS)
        if AVCaptureDevice.authorizationStatus(for: .audio) == .restricted { return .restricted }
        #endif
        switch AVAudioApplication.shared.recordPermission {
        case .granted: return .granted
        case .denied: return .denied
        default: return .undetermined
        }
    }

    func requestMicPermission() async -> MicPermission {
        if micPermission == .undetermined {
            _ = await AVAudioApplication.requestRecordPermission()
        }
        return micPermission
    }

    /// Recording is active: switching to it would interrupt a playing click (AU-5).
    var isRecordingActive: Bool {
        #if os(iOS)
        return session.role == .playAndRecord
        #else
        return true
        #endif
    }

    /// For the metronome and note sounds: playback category unless recording is already active.
    func ensurePlayback() throws {
        #if os(iOS)
        if session.role == nil {
            try session.activate(.playbackOnly)
            if host.engine.isRunning { try host.restart() }
        }
        #endif
        applyLatency()
    }

    /// For the tuner, trainer and smart mode: record + play in `.measurement` (AU-1, AU-5).
    func ensureRecording() throws {
        #if os(iOS)
        let before = session.role
        try session.activate(.playAndRecord)
        if before != .playAndRecord && host.engine.isRunning { try host.restart() }
        #endif
        applyLatency()
    }

    var inputSampleRate: Double { host.inputSampleRate }

    func startInput(pipeline: TunerPipeline, channel: Int) throws {
        try host.startInput(channel: channel, pipeline: pipeline)
    }

    func stopInput() { host.stopInput() }

    func playNote(_ pitch: Pitch, a4: Double, string: Int? = nil) {
        try? ensurePlayback()
        try? host.playNote(frequency: pitch.frequency(a4: a4), string: string)
    }
}
