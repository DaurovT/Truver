#if canImport(AVFoundation)
import AVFoundation
import os
import TruverDSP
import TruverTheory

/// One tick of the beat timeline with the host time when it is heard (output latency included, ME-12).
public struct TimelineTick: Sendable {
    public var event: ClickEvent
    /// `mach_absolute_time` units.
    public var hostTime: UInt64
}

/// Owns the AVAudioEngine: metronome output through a source node and microphone input through a tap.
/// Input analysis runs only while something needs it (AU-4).
public final class AudioEngineHost: @unchecked Sendable {
    public let engine = AVAudioEngine()

    /// Extra output delay added to tick times (Bluetooth compensation ME-9, measured or from the system).
    public var outputLatency: TimeInterval {
        get { latency.value }
        set { latency.value = newValue }
    }

    /// Lock-free: the render thread never waits and no tick is lost while the UI reads (PRD 13).
    private let timeline = SPSCRing<TimelineTick>(capacity: 1024, filler: TimelineTick(event: .placeholder, hostTime: 0))
    private let latency = AtomicDouble(0)
    private let render = RenderState()
    private var sourceNode: AVAudioSourceNode?
    private var inputInstalled = false
    private let analysisQueue = DispatchQueue(label: "truver.analysis", qos: .userInteractive)
    private var configurationObserver: NSObjectProtocol?

    /// Called on the main queue after the engine was restarted because its configuration changed
    /// (route or sample-rate change, AU-7). The input tap is removed at that point: the owner restarts the
    /// tuner with a pipeline for the new input format.
    public var onConfigurationChange: (@Sendable () -> Void)?

    /// Raw input observer (diagnostics, latency loopback): mono samples of the selected channel, host time of
    /// the first sample (`mach_absolute_time` units, 0 if the system did not provide it) and the sample rate.
    /// Called on the tap thread.
    public var onInputBlock: (@Sendable (_ samples: [Float], _ hostTime: UInt64, _ sampleRate: Double) -> Void)?

    public init() {
        // Give the graph an output path from the start. An engine whose only active node is an input tap may stop
        // on its own shortly after a tap is removed and installed again (seen on iPhone, iOS 26.5).
        _ = engine.mainMixerNode
        configurationObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main) { [weak self] _ in
            self?.handleConfigurationChange()
        }
    }

    deinit {
        if let configurationObserver { NotificationCenter.default.removeObserver(configurationObserver) }
    }

    public var isMetronomeRunning: Bool {
        var running = false
        render.perform { running = $0.clock.isRunning }
        return running
    }

    /// Restarts the engine after an audio-session category change (AU-5). The metronome keeps playing with its
    /// current settings; the input tap is removed and must be installed again with the new input format.
    public func restart() throws {
        stopInput()
        engine.stop()
        try reattachIfSampleRateChanged()
        try engine.start()
    }

    // MARK: Notes (TU-9, FB-7, FB-8, FB-13)

    public enum NoteStart: Sendable {
        /// As soon as possible (plus `delay` seconds).
        case now(delay: TimeInterval)
        /// On the next bar of the running metronome; if it is stopped, after `delay` seconds.
        case nextBar(fallbackDelay: TimeInterval)
        /// At an exact sample of the output timeline (the next cycle of a looping scale, gapless).
        case sample(Int64)
    }

    /// Sample time of the first note of the last `playNotes` call, and the output rate — for gapless loops.
    public private(set) var lastNotesStartSample: Int64 = 0
    public var noteSampleRate: Double { render.renderer?.clock.sampleRate ?? outputSampleRate }

    /// Plays notes at offsets (seconds) from the start point. Returns the time in seconds from now until the
    /// first note is heard, for highlighting the playing note.
    @discardableResult
    public func playNotes(_ notes: [(frequency: Double, offset: TimeInterval)], start: NoteStart = .now(delay: 0.03),
                          kind: NoteSynth.Kind = .pluck, velocity: Double = 0.8, strings: [Int]? = nil,
                          noteDuration: TimeInterval? = nil) throws -> TimeInterval {
        if !engine.isRunning {
            engine.prepare()
            try engine.start()
        }
        ensureOutput()
        var lead: TimeInterval = 0
        var startOfNotes: Int64 = 0
        let latency = outputLatency
        render.perform { box in
            let rate = box.synth.sampleRate
            let now = box.renderedFrames + Int64(0.01 * rate)   // safely after the buffer being rendered
            var startSample: Int64
            switch start {
            case .now(let delay):
                startSample = now + Int64(delay * rate)
            case .nextBar(let fallback):
                startSample = box.clock.nextBarStart() ?? (now + Int64(fallback * rate))
                if startSample < now { startSample = now }
            case .sample(let s):
                startSample = max(now, s)
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

    public func playNote(frequency: Double, kind: NoteSynth.Kind = .pluck, string: Int? = nil) throws {
        try playNotes([(frequency, 0)], kind: kind, strings: string.map { [$0] })
    }

    /// Debug: records the main mixer output to a WAV file for `seconds`.
    public func debugRecordOutput(to url: URL, seconds: Double) {
        let mixer = engine.mainMixerNode
        let format = mixer.outputFormat(forBus: 0)
        guard let file = try? AVAudioFile(forWriting: url, settings: format.settings) else { return }
        nonisolated(unsafe) let output = file
        mixer.installTap(onBus: 0, bufferSize: 4096, format: format) { buffer, _ in try? output.write(from: buffer) }
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { [weak self] in
            self?.engine.mainMixerNode.removeTap(onBus: 0)
            print("RECORDED", url.path)
        }
    }

    /// Debug: voices in the note synth and the rendered frame count.
    public func debugNoteState() -> (voices: Int, frames: Int64, metronomeRunning: Bool, peak: Float) {
        var result = (0, Int64(0), false, Float(0))
        render.perform { result = ($0.synth.activeVoiceCount, $0.renderedFrames, $0.clock.isRunning, $0.synth.lastBlockPeak) }
        return result
    }

    public func stopNotes() {
        render.perform { $0.synth.stopAll() }
    }

    private func handleConfigurationChange() {
        try? restart()
        onConfigurationChange?()
    }

    private func reattachIfSampleRateChanged() throws {
        let rate = engine.outputNode.inputFormat(forBus: 0).sampleRate
        guard rate > 0, let old = render.renderer, old.clock.sampleRate != rate else { return }
        let wasRunning = old.clock.isRunning
        let clock = MetronomeClock(sampleRate: rate, settings: old.clock.settings, modes: old.clock.modes)
        render.install(MetronomeRenderer(clock: clock, sounds: .make(clickSound, sampleRate: rate, accentDB: accentDB)), synth: NoteSynth(sampleRate: rate))
        attachSourceNode(sampleRate: rate)
        applyVolumes()
        if wasRunning { render.perform { $0.clock.start(atSample: $0.renderedFrames) } }
    }

    // MARK: Metronome output

    private var outputSampleRate: Double {
        let rate = engine.outputNode.inputFormat(forBus: 0).sampleRate
        return rate > 0 ? rate : 48_000
    }

    /// Creates the output graph (metronome clock, click renderer, note synth) for the current output rate.
    private func ensureOutput(settings: MeterSettings = MeterSettings(), modes: TrainingModes = .none) {
        let sampleRate = outputSampleRate
        guard sourceNode == nil || render.renderer?.clock.sampleRate != sampleRate else { return }
        // The output rate can change once the engine starts (first sound after launch). Carry the running clock
        // over — otherwise a metronome started a moment ago silently disappears (scale count-in without clicks).
        let old = render.renderer?.clock
        let clock = MetronomeClock(sampleRate: sampleRate, settings: old?.settings ?? settings, modes: old?.modes ?? modes)
        render.install(MetronomeRenderer(clock: clock, sounds: .make(clickSound, sampleRate: sampleRate, accentDB: accentDB)),
                       synth: NoteSynth(sampleRate: sampleRate))
        attachSourceNode(sampleRate: sampleRate)
        applyVolumes()
        if old?.isRunning == true { render.perform { $0.clock.start(atSample: $0.renderedFrames) } }
    }

    /// Starts the metronome. Settings and modes go to the clock, which applies them at beat or bar boundaries.
    public func startMetronome(settings: MeterSettings, modes: TrainingModes = .none) throws {
        // Start the engine first, then build the graph for its final output rate (the rate may change on the first
        // start). Bug «второе нажатие включает метроном вместо гаммы»: the graph was rebuilt after the clock started.
        if !engine.isRunning {
            engine.prepare()
            try engine.start()
        }
        ensureOutput(settings: settings, modes: modes)
        render.perform { renderer in
            renderer.clock.update(settings)
            renderer.clock.setModes(modes)
            renderer.clock.start(atSample: renderer.renderedFrames)
        }
        if !engine.isRunning { try engine.start() }
    }

    /// SND-7: click, notes and chords, reference tone — 0…1 each; kept across graph rebuilds.
    public private(set) var volumes: (click: Float, notes: Float, reference: Float) = (0.8, 0.6, 0.5)

    public func setVolumes(click: Float, notes: Float, reference: Float) {
        volumes = (click, notes, reference)
        applyVolumes()
    }

    private func applyVolumes() {
        let v = volumes
        render.perform { box in
            box.renderer.volume = v.click * 0.75      // 80 % → 0.6, the level balanced against notes
            box.synth.volume = v.notes                // 60 % → 0.6
            box.synth.referenceVolume = v.reference * 1.2
        }
    }

    /// Click set; switching applies to the next click.
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

    /// FB-13: drone on `frequency` until `stopDrone()`; the reference-tone slider sets its level (SND-7).
    public func startDrone(frequency: Double) throws {
        if !engine.isRunning {
            engine.prepare()
            try engine.start()
        }
        ensureOutput()
        render.perform { $0.synth.startDrone(frequency: frequency) }
    }

    public func stopDrone() {
        render.perform { $0.synth.stopDrone() }
    }

    /// SND-3: «цель достигнута» / «таймер истёк», 6 dB under the strong click of the current set, ~30 ms ahead.
    public func playEvent(_ sound: EventSound) throws {
        if !engine.isRunning {
            engine.prepare()
            try engine.start()
        }
        ensureOutput()
        render.perform { box in
            let samples = EventSounds.make(sound, sampleRate: box.clock.sampleRate, clicks: box.renderer.sounds)
            box.renderer.scheduleEvent(sound, samples: samples, at: box.renderedFrames + Int64(0.03 * box.clock.sampleRate))
        }
    }

    public func stopMetronome() {
        render.perform { renderer in
            renderer.clock.stop()
            renderer.stopAllVoices()
        }
    }

    /// Tempo, meter, accents: from the next beat; presets: from the next bar (ME-1, 6.2.6).
    public func updateMetronome(_ settings: MeterSettings, at moment: ApplyMoment = .nextBeat) {
        render.perform { $0.clock.update(settings, at: moment) }
    }

    /// Ticks rendered since the last call, for flash, vibration and the beat strip.
    public func drainTimeline() -> [TimelineTick] { timeline.drain() }

    /// Ticks dropped because nobody drained the timeline (diagnostics).
    public var droppedTimelineTicks: Int { timeline.droppedCount }

    public func drainNotices() -> [MetronomeNotice] {
        var result: [MetronomeNotice] = []
        render.perform { result = $0.clock.drainNotices() }
        return result
    }

    private func attachSourceNode(sampleRate: Double) {
        if let old = sourceNode { engine.detach(old) }
        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!
        let state = render
        let timeline = self.timeline
        let latency = self.latency
        let node = AVAudioSourceNode(format: format) { _, timestamp, frameCount, bufferList -> OSStatus in
            let buffers = UnsafeMutableAudioBufferListPointer(bufferList)
            guard let data = buffers.first?.mData?.assumingMemoryBound(to: Float.self) else { return noErr }
            let frames = Int(frameCount)
            let hostBase = timestamp.pointee.mFlags.contains(.hostTimeValid) ? timestamp.pointee.mHostTime : mach_absolute_time()
            let extra = latency.value
            state.renderIfAvailable(into: data, frameCount: frames) { event, blockStart in
                let offset = Double(event.sampleTime - blockStart) / sampleRate + extra
                timeline.push(TimelineTick(event: event, hostTime: hostBase + AVAudioTime.hostTime(forSeconds: max(0, offset))))
            }
            return noErr
        }
        engine.attach(node)
        engine.connect(node, to: engine.mainMixerNode, format: format)
        sourceNode = node
    }

    // MARK: Microphone input (AU-2, AU-4)

    /// Starts delivering mono input to `pipeline`. `channel` picks the interface input (guitar often on 2 → index 1).
    public func startInput(channel: Int = 0, pipeline: TunerPipeline) throws {
        stopInput()
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else { throw AudioHostError.noInput }
        let channelIndex = min(channel, Int(format.channelCount) - 1)
        let queue = analysisQueue
        let observer = onInputBlock
        let rate = format.sampleRate
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, when in
            guard let channels = buffer.floatChannelData else { return }
            let samples = Array(UnsafeBufferPointer(start: channels[channelIndex], count: Int(buffer.frameLength)))
            observer?(samples, when.isHostTimeValid ? when.hostTime : 0, rate)
            queue.async { pipeline.process(samples) }
        }
        inputInstalled = true
        if !engine.isRunning {
            engine.prepare()
            try engine.start()
        }
    }

    /// Starts the engine again if the system stopped it (watchdog for the tuner and the metronome).
    @discardableResult
    public func ensureRunning() -> Bool {
        guard !engine.isRunning, inputInstalled || isMetronomeRunning else { return engine.isRunning }
        engine.prepare()
        return (try? engine.start()) != nil
    }

    public func stopInput() {
        guard inputInstalled else { return }
        engine.inputNode.removeTap(onBus: 0)
        inputInstalled = false
    }

    public var inputSampleRate: Double { engine.inputNode.outputFormat(forBus: 0).sampleRate }

    public func stopEngine() {
        stopInput()
        stopMetronome()
        engine.stop()
    }
}

public enum AudioHostError: Error {
    case noInput
}

/// Minimal `os_unfair_lock` wrapper without escaping or `@Sendable` closures, safe to try from the render thread.
class UnfairLock: @unchecked Sendable {
    private let pointer: UnsafeMutablePointer<os_unfair_lock>

    init() {
        pointer = .allocate(capacity: 1)
        pointer.initialize(to: os_unfair_lock())
    }

    deinit {
        pointer.deinitialize(count: 1)
        pointer.deallocate()
    }

    func lock() { os_unfair_lock_lock(pointer) }
    func unlock() { os_unfair_lock_unlock(pointer) }
    func tryLock() -> Bool { os_unfair_lock_trylock(pointer) }

    func withLock<T>(_ body: () throws -> T) rethrows -> T {
        lock()
        defer { unlock() }
        return try body()
    }
}

/// Renderer shared between the render thread and the control side. The render thread never blocks: if the
/// lock is taken by a control call, it outputs silence for that buffer (a rare, inaudible gap is better than
/// priority inversion).
final class RenderState: @unchecked Sendable {
    final class Box {
        let renderer: MetronomeRenderer
        let synth: NoteSynth
        var renderedFrames: Int64 = 0
        init(_ renderer: MetronomeRenderer, synth: NoteSynth) {
            self.renderer = renderer
            self.synth = synth
        }
        var clock: MetronomeClock { renderer.clock }
        func stopAllVoices() { renderer.stopAllVoices() }
    }

    private let lock = UnfairLock()
    private var box: Box?

    var renderer: MetronomeRenderer? { lock.withLock { box?.renderer } }

    func install(_ renderer: MetronomeRenderer, synth: NoteSynth) {
        lock.withLock { box = Box(renderer, synth: synth) }
    }

    func perform(_ body: (Box) -> Void) {
        lock.withLock { if let box { body(box) } }
    }

    func renderIfAvailable(into data: UnsafeMutablePointer<Float>, frameCount: Int,
                           onEvent: (ClickEvent, Int64) -> Void) {
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
        box.renderer.render(into: data, frameCount: frameCount, sampleTime: start) { onEvent($0, start) }
        box.synth.render(adding: data, frameCount: frameCount, sampleTime: start)
        box.renderedFrames += Int64(frameCount)
    }
}

/// Runs the pitch tracker on the analysis queue and reports to the main actor.
public final class TunerPipeline: @unchecked Sendable {
    private let tracker: PitchTracker
    private let onUpdate: @Sendable (TunerUpdate) -> Void
    /// Pause requests from the main thread, applied on the analysis queue (lock-free).
    private let pauseRequest = AtomicDouble(0)

    /// `onUpdate` is called on the main queue for every analysis hop.
    public init(configuration: TunerConfiguration, tuning: Tuning, mode: TunerMode,
                onUpdate: @escaping @Sendable (TunerUpdate) -> Void) {
        self.tracker = PitchTracker(configuration: configuration, tuning: tuning, mode: mode)
        self.onUpdate = onUpdate
    }

    /// Pauses the analysis for `seconds` around a haptic pulse (the built-in microphone hears it).
    public func pauseAnalysis(seconds: Double = 0.05) {
        pauseRequest.value = seconds
    }

    /// Called on the analysis queue only.
    func process(_ samples: [Float]) {
        let pause = pauseRequest.value
        if pause > 0 {
            pauseRequest.value = 0
            tracker.pauseAnalysis(seconds: pause)
        }
        let updates = tracker.process(samples)
        guard !updates.isEmpty else { return }
        let callback = onUpdate
        DispatchQueue.main.async {
            for update in updates { callback(update) }
        }
    }
}

extension Array {
    subscript(safe index: Int) -> Element? { indices.contains(index) ? self[index] : nil }
}

#endif
