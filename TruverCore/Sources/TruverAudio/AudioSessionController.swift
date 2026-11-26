#if canImport(AVFoundation)
#if os(iOS)
import AVFoundation

/// iOS audio session policy (AU-1, AU-3, AU-5, AU-6, AU-7, AU-8).
@MainActor
public final class AudioSessionController {
    public enum Role: Equatable, Sendable {
        /// Metronome only: playback category, the microphone is not used and the orange indicator is off.
        case playbackOnly
        /// Tuner, trainer or smart mode: record + play, output on the main speaker.
        case playAndRecord
    }

    /// `.measurement` keeps the input raw (AU-1). AU-6: if the stage-0 spike shows the speaker gets too quiet
    /// and the low end survives in `.default`, switch this to `.default`.
    public var recordingMode: AVAudioSession.Mode = .measurement

    public private(set) var role: Role?
    public var onInterruption: ((_ began: Bool, _ shouldResume: Bool) -> Void)?
    public var onRouteChange: ((AVAudioSession.RouteChangeReason) -> Void)?

    // Written only in init, read in deinit: no concurrent access.
    nonisolated(unsafe) private var observers: [NSObjectProtocol] = []
    private let session = AVAudioSession.sharedInstance()

    public init() {
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] note in
            let info = note.userInfo ?? [:]
            let type = (info[AVAudioSessionInterruptionTypeKey] as? UInt).flatMap(AVAudioSession.InterruptionType.init(rawValue:))
            let options = (info[AVAudioSessionInterruptionOptionKey] as? UInt).map(AVAudioSession.InterruptionOptions.init(rawValue:)) ?? []
            MainActor.assumeIsolated {
                self?.onInterruption?(type == .began, options.contains(.shouldResume))
            }
        })
        observers.append(center.addObserver(forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main) { [weak self] note in
            let raw = note.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt
            let reason = raw.flatMap(AVAudioSession.RouteChangeReason.init(rawValue:)) ?? .unknown
            MainActor.assumeIsolated {
                self?.onRouteChange?(reason)
            }
        })
    }

    deinit {
        for observer in observers { NotificationCenter.default.removeObserver(observer) }
    }

    /// Switches the category. Call only when a module starts or stops, never during playing (AU-5):
    /// the switch causes a short gap in the sound.
    public func activate(_ newRole: Role) throws {
        guard newRole != role else { return }
        switch newRole {
        case .playbackOnly:
            try session.setCategory(.playback, mode: .default, options: [])
        case .playAndRecord:
            // No HFP: the microphone of Bluetooth headsets is never used; A2DP keeps playback quality (AU-3).
            try session.setCategory(.playAndRecord, mode: recordingMode, options: [.defaultToSpeaker, .allowBluetoothA2DP])
            try preferWiredOrBuiltInInput()
        }
        try session.setActive(true)
        role = newRole
    }

    public func deactivate() throws {
        try session.setActive(false, options: .notifyOthersOnDeactivation)
        role = nil
    }

    /// Wired interface first, built-in microphone otherwise (AU-3, AU-7).
    public func preferWiredOrBuiltInInput() throws {
        let inputs = session.availableInputs ?? []
        let wired = inputs.first { [.usbAudio, .lineIn, .headsetMic].contains($0.portType) }
        let builtIn = inputs.first { $0.portType == .builtInMic }
        if let port = wired ?? builtIn { try session.setPreferredInput(port) }
    }

    /// Inputs for the settings screen (AU-2): port name and channel count.
    public var availableInputs: [(name: String, uid: String, channels: Int)] {
        (session.availableInputs ?? []).map { (Self.displayName($0), $0.uid, $0.channels?.count ?? 1) }
    }

    /// The input in use and where the sound goes («Микрофон», «Динамик», «AirPods»).
    public var currentInputUID: String? { session.currentRoute.inputs.first?.uid }
    public var currentInputName: String? {
        guard let port = session.currentRoute.inputs.first else { return nil }
        return port.portType == .builtInMic ? "Микрофон" : port.portName
    }

    /// «Встроенный микрофон» instead of the system port name («MicrophoneBuiltIn», «iPhone Микрофон»).
    static func displayName(_ port: AVAudioSessionPortDescription) -> String {
        port.portType == .builtInMic ? "Встроенный микрофон" : port.portName
    }
    public var currentOutputName: String? {
        guard let port = session.currentRoute.outputs.first else { return nil }
        return port.portType == .builtInSpeaker ? "Динамик" : port.portName
    }

    public func selectInput(uid: String) throws {
        guard let port = session.availableInputs?.first(where: { $0.uid == uid }) else { return }
        try session.setPreferredInput(port)
    }

    /// Output latency for the beat timeline (ME-12) and flash sync: time from the render timestamp to sound.
    /// The render callback's host time already refers to the output of that buffer, so the IO buffer is not added
    /// (measured by acoustic loopback on iPhone 16 Pro Max: residual ≈ 0.1 ms with this value, −23 ms with the
    /// buffer added).
    public var outputLatency: TimeInterval { session.outputLatency }
    public var inputLatency: TimeInterval { session.inputLatency }

    // MARK: Microphone permission (AU-8)

    public enum Permission: Sendable { case undetermined, granted, denied }

    public static var microphonePermission: Permission {
        switch AVAudioApplication.shared.recordPermission {
        case .granted: return .granted
        case .denied: return .denied
        default: return .undetermined
        }
    }

    public static func requestMicrophonePermission() async -> Bool {
        await AVAudioApplication.requestRecordPermission()
    }
}
#endif

#endif
