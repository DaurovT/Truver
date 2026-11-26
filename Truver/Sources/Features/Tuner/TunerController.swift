import Foundation
import Observation
import TruverAudio
import TruverDSP
import TruverTheory
#if os(iOS)
import AVFoundation
import UIKit
#endif

/// Tuner screen state (6.2.4) on top of the core pitch tracker.
@MainActor
@Observable
final class TunerController {
    weak var app: AppModel?

    enum Mode: Equatable { case auto, chromatic, manual(StringRef) }

    /// Last known state of each string, shown as the coloured bar under its button (design: green = in tune,
    /// blue = flat, orange = sharp, neutral = not played yet).
    enum StringStatus: Equatable { case unknown, flat, sharp, inTune }

    var mode: Mode = .auto { didSet { if isListening { restartPipeline() } } }
    /// Noise threshold of the pro panel (TU-3).
    var noiseGate: Double = -55 { didSet { if isListening { restartPipeline() } } }
    /// TU-10: strobe view — the ring follows the signal phase, cents to a tenth.
    var strobeView = UserDefaults.standard.bool(forKey: "tuner.strobe") {
        didSet {
            UserDefaults.standard.set(strobeView, forKey: "tuner.strobe")
            strobe = nil
            if isListening { restartPipeline() }
        }
    }
    private(set) var strobe: StrobeReading?
    /// Range of the «Порог шума» slider (canvas «Тюнер — дополнительно»: −55 дБ sits at 45 % of the track).
    static let noiseGateRange: ClosedRange<Double> = -73 ... -33
    /// TU-12 stage view (opened from «Ещё»).
    var showStage = false

    // MARK: Route notices (canvas «Тюнер — Bluetooth», «Интерфейс отключён», «Вход переключён»)

    enum RouteNotice: Equatable {
        /// Bluetooth output: the headset mic is not used, the output lags (`latency` ms).
        case bluetooth(name: String, latency: Int)
        /// The interface went away; the tuner listens to the built-in microphone.
        case disconnected(name: String)
        /// Another input took over: «Слушаю Focusrite 2i2 · вход 1 (гитара)».
        case inputSwitched(text: String)
    }

    var notice: RouteNotice? { didSet { scheduleNoticeEnd() } }
    private var noticeTask: Task<Void, Never>?
    /// The last external input, named in «… пропал» when it goes away.
    private var lastInterfaceName: String?

    /// Audio route changed (AU-7). Shown over the tuner; on other tabs — the app's toast.
    func routeChanged(disconnected: Bool, bluetoothOutput: String?, latency: Double, input: String?) {
        guard let app else { return }
        let onTuner = app.settings.lastTab == .tuner
        if disconnected {
            if onTuner { notice = .disconnected(name: lastInterfaceName ?? "Интерфейс") }
            else { app.show("Интерфейс отключён — вход переключён на микрофон", icon: .warning, iconColor: Theme.sharp) }
        } else if let output = bluetoothOutput {
            if onTuner { notice = .bluetooth(name: output, latency: max(1, Int((latency * 1000).rounded() / 10) * 10)) }
            else { app.show("Микрофон наушников не используется — слушаю встроенный", icon: .bluetooth, iconColor: Theme.flat) }
        } else if let input {
            lastInterfaceName = input
            let channel = UserDefaults.standard.integer(forKey: "tuner.inputChannel")
            if onTuner { notice = .inputSwitched(text: "Слушаю \(input) · вход \(channel + 1)") }
            else { app.show("Вход: \(input)", icon: .audioInterface) }
        }
    }

    /// «Звук в динамик»: the output goes to the built-in speaker.
    func routeToSpeaker() {
        #if os(iOS)
        try? AVAudioSession.sharedInstance().overrideOutputAudioPort(.speaker)
        #endif
    }

    /// The card with buttons stays until «Понятно»; the others leave by themselves.
    private func scheduleNoticeEnd() {
        noticeTask?.cancel()
        guard let notice else { return }
        if case .bluetooth = notice { return }
        let seconds: Double = { if case .disconnected = notice { return 6 }; return 3 }()
        noticeTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            if !Task.isCancelled { self?.notice = nil }
        }
    }

    // MARK: TU-11 «Проверка мензуры»

    enum IntonationStep: Equatable { case open, twelfth, result(Double) }
    private(set) var intonationCourse: Int?
    private(set) var intonationStep: IntonationStep = .open
    /// Results of this session by course (cents, 12th fret − octave).
    private(set) var intonationResults: [Int: Double] = [:]
    private(set) var intonationProgress: Double = 0
    /// «Слышу A2 — сыграйте струну 6»: a note that does not belong to the step.
    private(set) var intonationHint: String?
    private var intonationReadings: [Double] = []
    private var intonationOpen: Double?
    private var modeBeforeCheck: Mode?

    func beginIntonation(course: Int) {
        if modeBeforeCheck == nil { modeBeforeCheck = mode }
        if mode != .chromatic { mode = .chromatic }   // any note gives a reading
        intonationCourse = course
        intonationStep = .open
        intonationOpen = nil
        intonationReadings = []
        intonationProgress = 0
        intonationHint = nil
    }

    func repeatIntonationStep() {
        intonationReadings = []
        intonationProgress = 0
        intonationHint = nil
        if case .result = intonationStep, let course = intonationCourse { beginIntonation(course: course) }
    }

    #if DEBUG
    /// Canvas «Проверка мензуры»: step 1 on the lowest string, a wrong note heard, the first readings in.
    func injectIntonationDemo(hint: String) {
        beginIntonation(course: 0)
        intonationHint = hint
        intonationProgress = 0.06
    }
    #endif

    func endIntonation() {
        intonationCourse = nil
        if let previous = modeBeforeCheck { mode = previous }
        modeBeforeCheck = nil
    }

    private func feedIntonation(_ reading: TunerReading) {
        guard let course = intonationCourse, let app, !reading.isProvisional else { return }
        let f = reading.frequency
        let expected: Double
        switch intonationStep {
        case .open: expected = app.tuning.openPitch(course: course, string: 0).frequency(a4: app.a4)
        case .twelfth: expected = 2 * (intonationOpen ?? 0)
        case .result: return
        }
        let off = abs(1200 * log2(f / expected))
        guard off < (intonationStep == .open ? 150 : 100) else {
            // The other note still rings (the open string under the 12th fret) — ignore quietly near the octave.
            if intonationStep == .open || abs(1200 * log2(f / (expected / 2))) > 100 {
                intonationHint = "Слышу \(app.chromaticName(reading.pitch))"
            }
            return
        }
        intonationHint = nil
        intonationReadings.append(f)
        intonationProgress = min(1, Double(intonationReadings.count) / 16)
        guard let steady = Intonation.steadyFrequency(intonationReadings) else { return }
        if intonationStep == .open {
            intonationOpen = steady
            intonationStep = .twelfth
            intonationReadings = []
            intonationProgress = 0
            #if os(iOS)
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            #endif
        } else if let open = intonationOpen {
            let cents = Intonation.error(open: open, twelfth: steady)
            intonationResults[course] = cents
            intonationStep = .result(cents)
            #if os(iOS)
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            #endif
        }
    }
    private(set) var display: TunerDisplay = .idle
    private(set) var level: Double = -160
    private(set) var tuned: Set<StringRef> = []
    private(set) var allTuned = false
    private(set) var isListening = false
    private(set) var permission: MicPermission = .undetermined
    private(set) var referenceUntil: Date?
    private(set) var error: String?
    private(set) var stringStatus: [StringRef: StringStatus] = [:]
    /// The last reading, kept for the waiting state (the dial shows the last note) and the reference button.
    private(set) var lastReading: TunerReading?
    private(set) var lastString: StringRef?
    private(set) var referenceString: StringRef?

    private var pipeline: TunerPipeline?

    /// FB-23: while the app's own notes ring, the tuner does not take them for the player's string.
    func pauseForPlayback(seconds: Double) {
        pipeline?.pauseAnalysis(seconds: seconds)
    }

    var isReferencePlaying: Bool { (referenceUntil ?? .distantPast) > Date() }

    /// State 1 of 6.2.4: the metronome is playing and the category switch would interrupt it.
    var needsMicrophoneButton: Bool {
        guard let app else { return false }
        return !isListening && app.metronome.isPlaying && !app.audio.isRecordingActive
    }

    /// Starts listening when the tab opens (6.1 п. 1) unless that would interrupt the metronome.
    func start(confirmedGap: Bool = false) async {
        guard let app, !isListening else { return }
        permission = await app.audio.requestMicPermission()
        guard permission == .granted else { return }
        if app.metronome.isPlaying && !app.audio.isRecordingActive && !confirmedGap { return }
        do {
            try app.audio.ensureRecording()
            try installPipeline()
            isListening = true
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }

    func stop() {
        app?.audio.stopInput()
        pipeline = nil
        isListening = false
        display = .idle
    }

    func tuningChanged() {
        tuned = []
        allTuned = false
        stringStatus = [:]
        lastReading = nil
        lastString = nil
        if case .manual = mode { mode = .auto }
        if isListening { restartPipeline() }
    }

    func handleAudioRestart() {
        if isListening { restartPipeline() }
    }

    /// 6.2.4 #9: tap on a string selects it (manual mode); tap again returns to auto.
    func tapString(_ ref: StringRef) {
        mode = mode == .manual(ref) ? .auto : .manual(ref)
    }

    /// TU-9: reference tone of the selected (or given) string for 3 s; analysis pauses meanwhile (6.1 п. 5).
    /// A second tap while it sounds stops it (iPhone UX check: it restarted).
    func playReference(_ ref: StringRef) {
        guard let app else { return }
        if isReferencePlaying {
            stopReference()
            if referenceString == ref { return }
        }
        referenceString = ref
        let pitch = app.tuning.openPitch(course: ref.course, string: ref.string)
        try? app.audio.ensurePlayback()
        try? app.audio.host.playNotes([(pitch.frequency(a4: app.a4), 0)], kind: .reference(duration: 3))
        referenceUntil = Date().addingTimeInterval(3)
        referenceSecondsLeft = 3
        display = .idle
        // Live countdown «3 → 2 → 1 с» (it stood still: the text was computed only when something else changed).
        referenceTask?.cancel()
        referenceTask = Task { [weak self] in
            while let self, let until = self.referenceUntil, until > Date() {
                self.referenceSecondsLeft = max(1, Int(until.timeIntervalSinceNow.rounded(.up)))
                try? await Task.sleep(for: .milliseconds(200))
                if Task.isCancelled { return }
            }
            self?.referenceSecondsLeft = 0
            self?.referenceUntil = nil
        }
    }

    func stopReference() {
        referenceTask?.cancel()
        app?.audio.host.stopNotes()
        referenceUntil = nil
        referenceSecondsLeft = 0
    }

    /// Whole seconds left of the reference tone, updated live.
    private(set) var referenceSecondsLeft = 0
    private var referenceTask: Task<Void, Never>?

    /// The string the reference button plays: the manual one, else the last heard, else the lowest.
    var referenceTarget: StringRef {
        if case .manual(let ref) = mode { return ref }
        return lastString ?? StringRef(course: 0)
    }

    enum Choice: Hashable { case auto, manual, chromatic }

    /// Segmented control «Авто / Ручной / Хром.»; "Ручной" takes the last heard string (or the lowest).
    var choice: Choice {
        get {
            switch mode {
            case .auto: return .auto
            case .manual: return .manual
            case .chromatic: return .chromatic
            }
        }
        set {
            switch newValue {
            case .auto: mode = .auto
            case .chromatic: mode = .chromatic
            case .manual: if case .manual = mode {} else { mode = .manual(lastString ?? StringRef(course: 0)) }
            }
        }
    }

    func resetMarks() {
        tuned = []
        allTuned = false
        stringStatus = [:]
        if isListening { restartPipeline() }
    }

    private func restartPipeline() {
        app?.audio.stopInput()
        do { try installPipeline() } catch { self.error = error.localizedDescription }
    }

    private func installPipeline() throws {
        guard let app else { return }
        let rate = app.audio.inputSampleRate
        guard rate > 0 else { throw AudioHostError.noInput }
        var config = TunerConfiguration(sampleRate: rate)
        config.a4 = app.a4
        config.noiseGateDB = noiseGate
        config.strobe = strobeView
        let trackerMode: TunerMode
        switch mode {
        case .auto: trackerMode = .auto
        case .chromatic: trackerMode = .chromatic
        case .manual(let ref): trackerMode = .manual(course: ref.course, string: ref.string)
        }
        let pipeline = TunerPipeline(configuration: config, tuning: app.tuning, mode: trackerMode) { [weak self] update in
            MainActor.assumeIsolated { self?.apply(update) }
        }
        self.pipeline = pipeline
        try app.audio.startInput(pipeline: pipeline, channel: UserDefaults.standard.integer(forKey: "tuner.inputChannel"))
    }

    private func apply(_ update: TunerUpdate) {
        level = update.levelDB
        guard !isReferencePlaying else { return }
        display = update.display
        strobe = update.strobe
        if case .reading(let reading) = update.display, intonationCourse != nil { feedIntonation(reading) }
        if case .reading(let reading) = update.display { app?.trainer.hear(reading); app?.playCheck.hearPitch(reading) }
        if case .reading(let reading) = update.display {
            app?.practice.activity(tuned: false)
            lastReading = reading
            if case let .string(ref, _, deviation) = reading.target {
                lastString = ref
                if reading.isInTune || (tuned.contains(ref) && abs(deviation) <= 5) {
                    stringStatus[ref] = .inTune
                } else {
                    stringStatus[ref] = deviation < 0 ? .flat : .sharp
                }
            }
        }
        for event in update.events {
            switch event {
            case .stringTuned(let ref):
                tuned.insert(ref)
                #if os(iOS)
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                #endif
            case .allStringsTuned:
                allTuned = true
                app?.practice.activity(tuned: true)
                #if os(iOS)
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                #endif
            }
        }
    }
}
