#if canImport(Darwin)
import Darwin
#elseif canImport(Android)
import Android
#elseif canImport(Glibc)
import Glibc
#endif
#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif
import Dispatch
import TruverDSP
import TruverTheory

/// One beat-timeline tick with the moment it is heard (monotonic ns, output latency and ME-9 offset included).
public struct HostTick: Sendable {
    public var event: ClickEvent
    public var hostNanos: Int64
}

/// Platform-neutral audio host for Android and Windows: the metronome clock and click renderer, the note synth
/// and the tuner pipeline on top of an `AudioBackend`. Mirrors `TruverAudio.AudioEngineHost` (iOS/macOS):
/// same render order, same volumes, same note scheduling, so the apps sound and time the same everywhere.
public final class AudioHost: @unchecked Sendable {
    public let backend: AudioBackend

    /// ME-9: extra output delay added to tick times (seconds).
    public var latencyOffset: Double {
        get { offset.value }
        set { offset.value = newValue }
    }

    private let render = HostRenderState()
    private let timeline = SPSCRing<HostTick>(capacity: 1024, filler: HostTick(event: .placeholder, hostNanos: 0))
    private let offset = AtomicDouble(0)
    private let control = PortableLock()
    private var outputRate: Double = 0

    public init(backend: AudioBackend) {
        self.backend = backend
        backend.onDisconnect = { [weak self] input in
            guard let host = self else { return }
            DispatchQueue.global().async { host.recover(input: input) }
        }
    }

    // MARK: Output graph

    /// Opens output if needed and builds the graph for its rate (carrying a running metronome over).
    private func ensureOutput(settings: MeterSettings = MeterSettings(), modes: TrainingModes = .none) throws {
        control.lock()
        defer { control.unlock() }
        if !backend.isOutputRunning {
            let state = render
            let timeline = self.timeline
            let offset = self.offset
            var rate: Double = 48_000
            rate = try backend.startOutput { buffer, frames, presentation in
                let extra = offset.value
                state.renderIfAvailable(into: buffer, frameCount: frames) { event, blockStart, sampleRate in
                    let seconds = Double(event.sampleTime - blockStart) / sampleRate + extra
                    _ = timeline.push(HostTick(event: event, hostNanos: presentation + Int64(max(0, seconds) * 1e9)))
                }
            }
            outputRate = rate
        }
        let rate = outputRate
        guard render.renderer?.clock.sampleRate != rate else { return }
        let old = render.renderer?.clock
        let clock = MetronomeClock(sampleRate: rate, settings: old?.settings ?? settings, modes: old?.modes ?? modes)
        render.install(MetronomeRenderer(clock: clock, sounds: .make(clickSound, sampleRate: rate, accentDB: accentDB)),
                       synth: NoteSynth(sampleRate: rate))
        applyVolumes()
        if old?.isRunning == true { render.perform { $0.clock.start(atSample: $0.renderedFrames) } }
    }

    private func recover(input: Bool) {
        if input {
            if let tuner = tunerSession { try? startTuner(configuration: tuner.configuration, tuning: tuner.tuning,
                                                           mode: tuner.mode, channel: tuner.channel) }
        } else {
            let wasRunning = isMetronomeRunning
            backend.stopOutput()
            if wasRunning || render.renderer != nil { try? ensureOutput() }
        }
    }

    public var isMetronomeRunning: Bool {
        var running = false
        render.perform { running = $0.clock.isRunning }
        return running
    }

    // MARK: Metronome (ME-1…ME-12)

    public func startMetronome(settings: MeterSettings, modes: TrainingModes = .none) throws {
        try ensureOutput(settings: settings, modes: modes)
        render.perform { box in
            box.clock.update(settings)
            box.clock.setModes(modes)
            box.clock.start(atSample: box.renderedFrames)
        }
    }

    public func stopMetronome() {
        render.perform { box in
            box.clock.stop()
            box.renderer.stopAllVoices()
        }
    }

    public func updateMetronome(_ settings: MeterSettings, at moment: ApplyMoment = .nextBeat) {
        render.perform { $0.clock.update(settings, at: moment) }
    }

    public func setModes(_ modes: TrainingModes) {
        render.perform { $0.clock.setModes(modes) }
    }

    public func drainTimeline() -> [HostTick] { timeline.drain() }

    public func drainNotices() -> [MetronomeNotice] {
        var result: [MetronomeNotice] = []
        render.perform { result = $0.clock.drainNotices() }
        return result
    }

    // MARK: Volumes and sounds (SND-1, SND-7)

    public private(set) var volumes: (click: Float, notes: Float, reference: Float) = (0.8, 0.6, 0.5)

    public func setVolumes(click: Float, notes: Float, reference: Float) {
        volumes = (click, notes, reference)
        applyVolumes()
    }

    private func applyVolumes() {
        let v = volumes
        render.perform { box in
            box.renderer.volume = v.click * 0.75
            box.synth.volume = v.notes
            box.synth.referenceVolume = v.reference * 1.2
        }
    }

    public var clickSound: ClickSounds.Kind = .click {
        didSet {
            guard clickSound != oldValue, let rate = render.renderer?.clock.sampleRate else { return }
            let sounds = ClickSounds.make(clickSound, sampleRate: rate, accentDB: accentDB)
            render.perform { $0.renderer.sounds = sounds }
        }
    }

    /// «Громкость акцента» (dB of the strong click over the normal one); applies to the next click.
    public var accentDB: Double = ClickSounds.defaultAccentDB {
        didSet {
            guard accentDB != oldValue, let rate = render.renderer?.clock.sampleRate else { return }
            let sounds = ClickSounds.make(clickSound, sampleRate: rate, accentDB: accentDB)
            render.perform { $0.renderer.sounds = sounds }
        }
    }

    // MARK: Notes (TU-9, FB-7, FB-8, FB-13, FB-23)

    public enum NoteStart: Sendable {
        case now(delay: Double)
        case nextBar(fallbackDelay: Double)
        case sample(Int64)
    }

    public private(set) var lastNotesStartSample: Int64 = 0
    public var noteSampleRate: Double { render.renderer?.clock.sampleRate ?? (outputRate > 0 ? outputRate : 48_000) }

    /// Plays notes at offsets (seconds) from the start point; returns seconds from now until the first is heard.
    @discardableResult
    public func playNotes(_ notes: [(frequency: Double, offset: Double)], start: NoteStart = .now(delay: 0.03),
                          kind: NoteSynth.Kind = .pluck, velocity: Double = 0.8, strings: [Int]? = nil,
                          noteDuration: Double? = nil) throws -> Double {
        try ensureOutput()
        var lead: Double = 0
        var startOfNotes: Int64 = 0
        let latency = latencyOffset
        render.perform { box in
            let rate = box.synth.sampleRate
            let now = box.renderedFrames + Int64(0.01 * rate)
            var startSample: Int64
            switch start {
            case .now(let delay): startSample = now + Int64(delay * rate)
            case .nextBar(let fallback):
                startSample = box.clock.nextBarStart() ?? (now + Int64(fallback * rate))
                if startSample < now { startSample = now }
            case .sample(let s): startSample = max(now, s)
            }
            startOfNotes = startSample
            for (i, note) in notes.enumerated() {
                box.synth.schedule(frequency: note.frequency, at: startSample + Int64(note.offset * rate),
                                   velocity: velocity, kind: kind, string: strings?[safe: i], duration: noteDuration)
            }
            lead = Double(startSample - box.renderedFrames) / rate + latency
        }
        lastNotesStartSample = startOfNotes
        return lead
    }

    public func stopNotes() { render.perform { $0.synth.stopAll() } }

    public func startDrone(frequency: Double) throws {
        try ensureOutput()
        render.perform { $0.synth.startDrone(frequency: frequency) }
    }

    public func stopDrone() { render.perform { $0.synth.stopDrone() } }

    public func playEvent(_ sound: EventSound) throws {
        try ensureOutput()
        render.perform { box in
            let samples = EventSounds.make(sound, sampleRate: box.clock.sampleRate, clicks: box.renderer.sounds)
            box.renderer.scheduleEvent(sound, samples: samples, at: box.renderedFrames + Int64(0.03 * box.clock.sampleRate))
        }
    }

    // MARK: Tuner input (AU-2, AU-4, TU-1…TU-10)

    private struct TunerSession {
        var configuration: TunerConfiguration
        var tuning: Tuning
        var mode: TunerMode
        var channel: Int
    }

    private var tunerSession: TunerSession?
    private var analysis: AnalysisThread?
    public private(set) var inputSampleRate: Double = 0

    /// Starts the microphone and the pitch tracker. `configuration.sampleRate` is replaced by the device rate.
    public func startTuner(configuration: TunerConfiguration, tuning: Tuning, mode: TunerMode, channel: Int = 0) throws {
        stopTuner()
        let ring = SampleRing(capacityPowerOfTwo: 1 << 16)
        let rate = try backend.startInput(channel: channel) { samples, frames, stride, _ in
            ring.write(samples, count: frames, stride: stride)
        }
        inputSampleRate = rate
        var config = configuration
        config.sampleRate = rate
        tunerSession = TunerSession(configuration: config, tuning: tuning, mode: mode, channel: channel)
        let thread = AnalysisThread(ring: ring, tracker: PitchTracker(configuration: config, tuning: tuning, mode: mode))
        analysis = thread
        thread.start()
    }

    public func stopTuner() {
        backend.stopInput()
        analysis?.cancel()
        analysis = nil
        tunerSession = nil
    }

    public var isTunerRunning: Bool { analysis != nil }

    /// Updates produced since the last call (the UI polls every frame).
    public func drainTunerUpdates() -> [TunerUpdate] { analysis?.drain() ?? [] }

    /// Pauses analysis around a haptic pulse or the app's own sound (FB-23).
    public func pauseAnalysis(seconds: Double) { analysis?.requestPause(seconds) }

    public var diagnostics: [String: String] { backend.diagnostics }
}

/// Renderer shared between the render thread and the control side; the render thread only tries the lock.
final class HostRenderState: @unchecked Sendable {
    final class Box {
        let renderer: MetronomeRenderer
        let synth: NoteSynth
        var renderedFrames: Int64 = 0
        init(_ renderer: MetronomeRenderer, synth: NoteSynth) {
            self.renderer = renderer
            self.synth = synth
        }
        var clock: MetronomeClock { renderer.clock }
    }

    private let lock = PortableLock()
    private var box: Box?

    var renderer: MetronomeRenderer? { lock.withLock { box?.renderer } }

    func install(_ renderer: MetronomeRenderer, synth: NoteSynth) {
        lock.withLock { box = Box(renderer, synth: synth) }
    }

    func perform(_ body: (Box) -> Void) {
        lock.withLock { if let box { body(box) } }
    }

    func renderIfAvailable(into data: UnsafeMutablePointer<Float>, frameCount: Int,
                           onEvent: (ClickEvent, Int64, Double) -> Void) {
        guard lock.tryLock() else {
            data.update(repeating: 0, count: frameCount)
            return
        }
        defer { lock.unlock() }
        guard let box else {
            data.update(repeating: 0, count: frameCount)
            return
        }
        let start = box.renderedFrames
        let rate = box.clock.sampleRate
        box.renderer.render(into: data, frameCount: frameCount, sampleTime: start) { onEvent($0, start, rate) }
        box.synth.render(adding: data, frameCount: frameCount, sampleTime: start)
        box.renderedFrames += Int64(frameCount)
    }
}

/// Reads the input ring and runs the pitch tracker off the real-time thread.
final class AnalysisThread: @unchecked Sendable {
    private let ring: SampleRing
    private let tracker: PitchTracker
    private let lock = PortableLock()
    private var updates: [TunerUpdate] = []
    private var cancelled = false
    private let pause = AtomicDouble(0)

    init(ring: SampleRing, tracker: PitchTracker) {
        self.ring = ring
        self.tracker = tracker
    }

    func start() {
        startThread { [self] in run() }
    }

    func cancel() { lock.withLock { cancelled = true } }

    func requestPause(_ seconds: Double) { pause.value = seconds }

    func drain() -> [TunerUpdate] {
        lock.withLock {
            defer { updates.removeAll(keepingCapacity: true) }
            return updates
        }
    }

    private func run() {
        let chunk = 1024
        let buffer = UnsafeMutablePointer<Float>.allocate(capacity: chunk)
        defer { buffer.deallocate() }
        while !lock.withLock({ cancelled }) {
            let p = pause.value
            if p > 0 {
                pause.value = 0
                tracker.pauseAnalysis(seconds: p)
            }
            let n = ring.read(into: buffer, maxCount: chunk)
            if n == 0 {
                usleep(3_000)
                continue
            }
            let produced = tracker.process(Array(UnsafeBufferPointer(start: buffer, count: n)))
            if !produced.isEmpty {
                lock.withLock {
                    updates.append(contentsOf: produced)
                    if updates.count > 400 { updates.removeFirst(updates.count - 400) }
                }
            }
        }
    }
}
