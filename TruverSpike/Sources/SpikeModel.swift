import AVFoundation
import Observation
import SwiftUI
import TruverAudio
import TruverDSP
import TruverTheory
#if os(iOS)
import UIKit
#else
import CoreAudio
#endif

enum MetronomeModeChoice: String, CaseIterable, Identifiable {
    case none = "Без режима"
    case speedUp = "Разгон +5 / 4 такта"
    case twoForward = "Два вперёд, один назад"
    case gapBars = "Пропадающие такты 2+2"
    case backbeats = "Щелчок на 2 и 4"
    case ladder = "Лесенка делений"

    var id: String { rawValue }

    func modes(from bpm: Double) -> TrainingModes {
        switch self {
        case .none: return .none
        case .speedUp: return TrainingModes(tempo: .speedUp(step: 5, every: .bars(4), target: min(400, bpm + 40)))
        case .twoForward: return TrainingModes(tempo: .twoForwardOneBack(step: 4, everyBars: 2, target: min(400, bpm + 40)))
        case .gapBars: return TrainingModes(sound: .gapBars(on: 2, off: 2, offGrowth: 0, maxOff: 2))
        case .backbeats: return TrainingModes(sound: .displacedClick(.backbeats))
        case .ladder: return TrainingModes(subdivision: .standardLadder)
        }
    }
}

/// State and audio control of the spike app. Everything runs on the main actor; audio work happens inside
/// TruverAudio (render thread, analysis queue).
@MainActor
@Observable
final class SpikeModel {
    // MARK: Instrument

    var templateId = "g7-standard-b" { didSet { applyTemplate() } }
    private(set) var instrument: Instrument
    var tuning: Tuning { instrument.currentTuning! }
    var a4: Double = 440 { didSet { if tunerRunning { restartTuner() } } }

    // MARK: Tuner

    enum TargetMode: Equatable { case auto, chromatic, manual(Int) }
    var targetMode: TargetMode = .auto { didSet { if tunerRunning { restartTuner() } } }
    private(set) var display: TunerDisplay = .idle
    private(set) var tuned: Set<StringRef> = []
    private(set) var allTuned = false
    private(set) var tunerRunning = false
    private(set) var micDenied = false
    var lastError: String?

    // MARK: Metronome

    var bpm: Double = 120 { didSet { pushMetronome() } }
    var numerator = 4 { didSet { pushMetronome() } }
    var subdivision = 1 { didSet { pushMetronome() } }
    var swing = 0.5 { didSet { pushMetronome() } }
    var modeChoice: MetronomeModeChoice = .none { didSet { if metronomeRunning { restartMetronome() } } }
    var vibration = false
    private(set) var metronomeRunning = false
    private(set) var currentBeat: Int?
    private(set) var currentBar = 0
    private(set) var flashOn = false
    private(set) var silentBar = false
    private(set) var liveBPM: Double = 120
    private(set) var lastNotice: String?
    private var pendingTicks: [TimelineTick] = []
    /// Autotest: every tick drained from the host is also kept here while recording.
    var recordedTicks: [TimelineTick]?
    var lastUpdate: TunerUpdate?
    var onTunerUpdate: ((TunerUpdate) -> Void)?
    private var updateCount = 0
    private var tickCount = 0

    /// Autotest counters since the last call.
    func takeCounters() -> (updates: Int, ticks: Int) {
        defer { updateCount = 0; tickCount = 0 }
        return (updateCount, tickCount)
    }
    private var tapTempo = TapTempo()
    private var loop: Task<Void, Never>?

    // MARK: Diagnostics

    var useMeasurementMode = true
    var inputChannel = 0 { didSet { if tunerRunning { restartTuner() } } }
    private(set) var sessionRole = "—"
    private(set) var latencyText = "—"
    private(set) var inputDescriptions: [String] = []
    #if os(macOS)
    private(set) var macDevices: [AudioInputDevice] = []
    var selectedDeviceID: AudioDeviceID? { didSet { selectMacDevice() } }
    #endif

    let host = AudioEngineHost()
    #if os(iOS)
    let session = AudioSessionController()
    private let haptic = UIImpactFeedbackGenerator(style: .rigid)
    #endif
    private var pipeline: TunerPipeline?

    init() {
        instrument = TuningTemplates.template(id: "g7-standard-b")!.makeInstrument()
        host.onConfigurationChange = { [weak self] in
            MainActor.assumeIsolated { self?.handleConfigurationChange() }
        }
        #if os(iOS)
        session.onInterruption = { [weak self] began, _ in
            // 6.1 п. 6: the metronome stops and does not resume by itself; the tuner resumes.
            guard let self else { return }
            if began {
                self.stopMetronome(notice: "Прервано — нажмите «Старт», чтобы продолжить")
            } else if self.tunerRunning {
                self.restartTuner()
            }
        }
        session.onRouteChange = { [weak self] reason in
            guard let self else { return }
            if reason == .oldDeviceUnavailable { self.lastNotice = "Вход переключён на микрофон (AU-7)" }
            if reason == .newDeviceAvailable { self.lastNotice = "Подключено новое устройство" }
            self.refreshDiagnostics()
        }
        #endif
        refreshDiagnostics()
    }

    // MARK: - Instrument

    private func applyTemplate() {
        guard let template = TuningTemplates.template(id: templateId) else { return }
        instrument = template.makeInstrument()
        targetMode = .auto
        tuned = []
        allTuned = false
        if tunerRunning { restartTuner() }
    }

    func noteName(for ref: StringRef) -> String {
        let pitch = tuning.openPitch(course: ref.course, string: ref.string)
        let main = tuning.spelledNotes[ref.course]
        return SpelledNote(main.name, midi: pitch.nearestMIDI).description
    }

    func noteName(for pitch: Pitch) -> String {
        let flats = tuning.spelledNotes.contains { $0.name.accidental < 0 }
        return SpelledNote(NoteName.simpleSpelling(ofPitchClass: pitch.pitchClass, preferFlats: flats),
                           midi: pitch.nearestMIDI).description
    }

    // MARK: - Tuner

    /// Starts listening (6.1 п. 1). While the metronome plays, the microphone is switched on only by an explicit
    /// tap, because the category change interrupts the click for a moment (AU-5).
    func startTuner(userConfirmedGap: Bool = false) async {
        guard !tunerRunning else { return }
        switch AVAudioApplication.shared.recordPermission {
        case .undetermined:
            let granted = await AVAudioApplication.requestRecordPermission()
            micDenied = !granted
            guard granted else { return }
        case .denied:
            micDenied = true
            return
        default:
            micDenied = false
        }
        #if os(iOS)
        if metronomeRunning && session.role != .playAndRecord && !userConfirmedGap { return }
        #endif
        do {
            try activateRecording()
            try installPipeline()
            tunerRunning = true
            lastError = nil
        } catch {
            lastError = "Звук недоступен: \(error.localizedDescription)"
        }
        refreshDiagnostics()
    }

    var needsMicrophoneButton: Bool {
        #if os(iOS)
        return metronomeRunning && !tunerRunning && session.role != .playAndRecord
        #else
        return false
        #endif
    }

    func stopTuner() {
        host.stopInput()
        pipeline = nil
        tunerRunning = false
        display = .idle
    }

    func restartTuner() {
        host.stopInput()
        do { try installPipeline() } catch { lastError = error.localizedDescription }
    }

    func resetTunedMarks() {
        tuned = []
        allTuned = false
        if tunerRunning { restartTuner() }
    }

    private func activateRecording() throws {
        #if os(iOS)
        session.recordingMode = useMeasurementMode ? .measurement : .default
        let before = session.role
        try session.activate(.playAndRecord)
        if before != .playAndRecord && host.engine.isRunning { try host.restart() }
        #endif
    }

    private func installPipeline() throws {
        let rate = host.inputSampleRate
        guard rate > 0 else { throw AudioHostError.noInput }
        var config = TunerConfiguration(sampleRate: rate)
        config.a4 = a4
        let mode: TunerMode
        switch targetMode {
        case .auto: mode = .auto
        case .chromatic: mode = .chromatic
        case .manual(let course): mode = .manual(course: course, string: 0)
        }
        let pipeline = TunerPipeline(configuration: config, tuning: tuning, mode: mode) { [weak self] update in
            MainActor.assumeIsolated { self?.apply(update) }
        }
        self.pipeline = pipeline
        try host.startInput(channel: inputChannel, pipeline: pipeline)
    }

    private func apply(_ update: TunerUpdate) {
        lastUpdate = update
        updateCount += 1
        onTunerUpdate?(update)
        display = update.display
        for event in update.events {
            switch event {
            case .stringTuned(let ref): tuned.insert(ref)
            case .allStringsTuned:
                allTuned = true
                #if os(iOS)
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                #endif
            }
        }
    }

    func tapString(_ course: Int) {
        // 6.2.4 #9: tap on a string button switches to manual mode; tap again returns to auto.
        targetMode = targetMode == .manual(course) ? .auto : .manual(course)
    }

    // MARK: - Metronome

    var meter: MeterSettings {
        MeterSettings(bpm: bpm, numerator: numerator, denominator: 4, subdivision: subdivision, swing: swing)
    }

    func toggleMetronome() {
        metronomeRunning ? stopMetronome() : startMetronome()
    }

    func startMetronome() {
        do {
            #if os(iOS)
            if session.role == nil {
                try session.activate(.playbackOnly)
                if host.engine.isRunning { try host.restart() }
            }
            host.outputLatency = session.outputLatency
            #else
            host.outputLatency = host.engine.outputNode.presentationLatency
            #endif
            try host.startMetronome(settings: meter, modes: modeChoice.modes(from: bpm))
            metronomeRunning = true
            liveBPM = bpm
            lastNotice = nil
            pendingTicks = []
            startLoop()
        } catch {
            lastError = "Метроном не запустился: \(error.localizedDescription)"
        }
        refreshDiagnostics()
    }

    func stopMetronome(notice: String? = nil) {
        host.stopMetronome()
        metronomeRunning = false
        currentBeat = nil
        flashOn = false
        loop?.cancel()
        loop = nil
        if let notice { lastNotice = notice }
    }

    private func restartMetronome() {
        stopMetronome()
        startMetronome()
    }

    private func pushMetronome() {
        guard metronomeRunning else { return }
        host.updateMetronome(meter)
    }

    func tap() {
        if let tempo = tapTempo.tap(at: Date().timeIntervalSinceReferenceDate) {
            bpm = tempo.rounded()
        }
    }

    /// Polls the beat timeline (~120 Hz) and lights the beat when its host time arrives (ME-12).
    private func startLoop() {
        loop?.cancel()
        loop = Task { [weak self] in
            while !Task.isCancelled {
                self?.pollTimeline()
                try? await Task.sleep(for: .milliseconds(8))
            }
        }
    }

    private func pollTimeline() {
        let drained = host.drainTimeline()
        pendingTicks += drained
        recordedTicks? += drained
        tickCount += drained.count
        let now = mach_absolute_time()
        let rule = FlashPolicy.rule(for: meter)
        while let tick = pendingTicks.first, tick.hostTime <= now {
            pendingTicks.removeFirst()
            let event = tick.event
            guard event.tick == 0 else { continue }
            currentBeat = event.beat
            currentBar = event.bar
            silentBar = event.isSilent
            liveBPM = event.bpm
            let flash = FlashPolicy.flashes(event, rule: rule, accents: meter.accents)
            if flash {
                flashOn = true
                Task { [weak self] in
                    try? await Task.sleep(for: .milliseconds(70))
                    self?.flashOn = false
                }
            }
            #if os(iOS)
            if vibration && !event.isSilent { haptic.impactOccurred(intensity: event.level == .strong ? 1 : 0.6) }
            #endif
        }
        for notice in host.drainNotices() {
            switch notice {
            case .tempoChanged(let value): lastNotice = "Темп: \(Int(value))"
            case .targetReached: lastNotice = "Цель достигнута"
            case .subdivisionChanged(let value): lastNotice = "Деление: \(value)"
            case .silentBarsStarted: lastNotice = "Тихие такты"
            case .silentBarsEnded: lastNotice = "Щелчок вернулся"
            }
        }
    }

    // MARK: - Diagnostics

    func refreshDiagnostics() {
        #if os(iOS)
        sessionRole = switch session.role {
        case .playbackOnly: "Воспроизведение (только метроном)"
        case .playAndRecord: "Запись и воспроизведение · \(session.recordingMode == .measurement ? ".measurement" : ".default")"
        case nil: "Не активна"
        }
        latencyText = String(format: "выход %.1f мс · вход %.1f мс", session.outputLatency * 1000, session.inputLatency * 1000)
        inputDescriptions = session.availableInputs.map { "\($0.name) — каналов: \($0.channels)" }
        #else
        macDevices = AudioDevices.inputDevices()
        sessionRole = "macOS"
        latencyText = String(format: "выход %.1f мс", host.engine.outputNode.presentationLatency * 1000)
        inputDescriptions = macDevices.map { "\($0.name) — каналов: \($0.inputChannels)" }
        #endif
    }

    #if os(iOS)
    func selectInput(_ index: Int) {
        let inputs = session.availableInputs
        guard inputs.indices.contains(index) else { return }
        try? session.selectInput(uid: inputs[index].uid)
        if tunerRunning { restartTuner() }
        refreshDiagnostics()
    }
    #endif

    #if os(macOS)
    private func selectMacDevice() {
        guard let id = selectedDeviceID, let device = macDevices.first(where: { $0.id == id }) else { return }
        let wasRunning = tunerRunning
        stopTuner()
        host.engine.stop()
        do {
            try AudioDevices.select(device, for: host.engine)
            if wasRunning { Task { await startTuner() } }
        } catch {
            lastError = "Не удалось выбрать устройство: \(error.localizedDescription)"
        }
    }
    #endif

    /// Re-applied after the system changed the audio route or format (AU-7).
    func applyMeasurementModeChange() {
        guard tunerRunning else { return }
        #if os(iOS)
        let wasMetronome = metronomeRunning
        stopTuner()
        try? session.deactivate()
        if wasMetronome { try? session.activate(.playbackOnly) }
        Task { await startTuner(userConfirmedGap: true) }
        #endif
    }

    private func handleConfigurationChange() {
        SpikeLog.shared.log("configurationChange", ["tuner": tunerRunning, "engine": host.engine.isRunning])
        // The host restarted the engine and removed the tap: install a pipeline for the new input format.
        if tunerRunning { restartTuner() }
        refreshDiagnostics()
    }
}
