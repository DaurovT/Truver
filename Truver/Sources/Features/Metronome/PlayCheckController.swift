import Foundation
import Observation
import SwiftUI
import TruverAudio
import TruverDSP
import TruverTheory

/// One finished attempt of «Проверка игры» (PL-3 summary, PL-4 history).
struct PlayAttempt: Codable, Identifiable, Equatable {
    var id = UUID()
    var date: Date
    var preset: String?
    var seconds: Double
    var startBPM: Double
    var endBPM: Double
    /// SM-9: the highest tempo with a clean step-up run.
    var ceiling: Double?
    /// Share of «точно + хорошо» over counted bars.
    var accurateShare: Double
    /// Mean signed deviation, ms (− rushes, + drags).
    var meanDeviation: Double
    /// Spread, ms.
    var spread: Double
    /// Beat with the largest mean deviation (0-based) and that deviation in ms.
    var weakestBeat: Int?
    var weakestBeatDeviation: Double?
    var bars: Int
    /// SM-3: tempo drift over silent bars, ms.
    var silenceDrift: Double?
    /// Per-beat mean deviation, ms (heat map, PL-4).
    var perBeat: [Int: Double] = [:]
}

/// «Проверка игры» (stage SM): the microphone hears the attacks (SM-1), each is bound to the expected note of the
/// beat timeline (SM-2, ME-12) and graded (SM-3, SM-4); bars drive the tempo (SM-8) and the ceiling (SM-9).
@MainActor
@Observable
final class PlayCheckController {
    weak var app: AppModel?

    struct Settings: Codable, Equatable {
        /// SM-8: tempo follows the result.
        var adaptive = true
        var step = 4
        var cleanBars = 4
    }

    var settings: Settings {
        didSet { if let data = try? JSONEncoder().encode(settings) { UserDefaults.standard.set(data, forKey: "playcheck.settings") } }
    }
    private(set) var isOn = false
    /// The newest graded notes, oldest first (deviation strip).
    private(set) var recent: [GradedNote] = []
    private(set) var lastBar: BarStats?
    /// The subdivision is shorter than 40 ms: the metronome plays, the rhythm is not graded (SM-4).
    private(set) var gradingUnavailable = false
    /// The last bar had no attack at all: nobody plays yet — it is not graded and does not move the tempo.
    private(set) var idle = false
    /// Built-in speaker: the click reaches the microphone (SM-7).
    private(set) var speakerMode = false
    private(set) var summary: PlayAttempt?
    private(set) var history: [PlayAttempt] = []

    private var box: AnalyzerBox?
    private var expected: [ExpectedNote] = []
    private var clickTimes: [Double] = []
    private var clickStrength: Double?
    private var adaptive = AdaptiveTempo()
    private var barStats: [BarStats] = []
    private var allGraded: [GradedNote] = []
    private var attemptStart: Date?
    private var startBPM = 0.0

    // MARK: SM-6 latency calibration by loopback (speaker → microphone)

    enum Calibration: Equatable { case idle, running(Double), done(Double), failed(String) }
    private(set) var calibration: Calibration = .idle
    private var calibrating = false
    private var calibrationClicks: [Double] = []

    /// Input + output pair the calibration belongs to.
    var routeKey: String {
        #if os(iOS)
        let s = app?.audio.session
        return "playcheck.offset.\(s?.currentInputName ?? "?")|\(s?.currentOutputName ?? "?")"
        #else
        return "playcheck.offset.mac"
        #endif
    }

    /// Residual delay of the microphone path measured by the loop (s), subtracted from attack times.
    var routeOffset: Double { UserDefaults.standard.double(forKey: routeKey) }

    /// «Нужна тишина» → clicks → median of attack − click. Built-in speaker only; headphones and interfaces use
    /// the system values (SM-6).
    func calibrate() async {
        guard let app, !calibrating else { return }
        let wasOn = isOn
        if !isOn { await enable() }
        guard isOn else { return }
        guard speakerMode else {
            calibration = .failed("Наушники или интерфейс: задержка берётся из системы, петля не нужна")
            return
        }
        calibrating = true
        defer { calibrating = false }
        calibration = .running(0)
        try? await Task.sleep(for: .milliseconds(600))
        // Quiet room?
        if let analyzer = box?.current, let until = analyzer.heardUntil {
            let loud = stride(from: until - 0.5, to: until, by: 0.05).filter { analyzer.isSounding(at: $0) }.count
            if loud > 6 { calibration = .failed("Слишком шумно — нужна тишина"); if !wasOn { disable() }; return }
        }
        calibrationClicks = []
        let wasPlaying = app.metronome.isPlaying
        if !wasPlaying { app.metronome.start() }
        for i in 1...35 {
            try? await Task.sleep(for: .milliseconds(100))
            calibration = .running(Double(i) / 35)
        }
        if !wasPlaying { app.metronome.stop() }
        try? await Task.sleep(for: .milliseconds(300))
        guard let analyzer = box?.current else { calibration = .failed("Щелчки не слышны"); return }
        var differences: [Double] = []
        for click in calibrationClicks {
            let near = analyzer.onsets(from: click - 0.06, to: click + 0.06)
            if let best = near.min(by: { abs($0.time - click) < abs($1.time - click) }) { differences.append(best.time - click) }
        }
        guard differences.count >= 4 else {
            calibration = .failed("Щелчки не слышны — сделайте громче или поднесите телефон")
            if !wasOn { disable() }
            return
        }
        let median = differences.sorted()[differences.count / 2]
        UserDefaults.standard.set(median, forKey: routeKey)
        calibration = .done(median)
        clickStrength = nil
        if !wasOn { disable() }
    }

    // MARK: Exercise (FB-14, SM-5): a note sequence played one per tick, pitches checked to a semitone.

    private struct Exercise {
        var pitches: [Pitch]
        var onNote: (Int) -> Void
        var onWrong: (Int) -> Void
    }
    private var exercise: Exercise?
    private var exerciseCounter = 0
    private var exerciseIndexByTime: [Double: Int] = [:]
    private var pitchHistory: [(time: Double, pitch: Pitch)] = []
    var hasExercise: Bool { exercise != nil }

    func beginExercise(pitches: [Pitch], onNote: @escaping (Int) -> Void, onWrong: @escaping (Int) -> Void) {
        exercise = pitches.isEmpty ? nil : Exercise(pitches: pitches, onNote: onNote, onWrong: onWrong)
        exerciseCounter = 0
        exerciseIndexByTime = [:]
        pitchHistory = []
    }

    func endExercise() {
        exercise = nil
        exerciseIndexByTime = [:]
    }

    /// Tuner readings while an exercise runs: the pitch of each attack is the first steady reading after it.
    func hearPitch(_ reading: TunerReading) {
        guard isOn, exercise != nil, !reading.isProvisional else { return }
        pitchHistory.append((PlayCheckAnalyzer.seconds(hostTime: mach_absolute_time()), reading.pitch))
        if pitchHistory.count > 400 { pitchHistory.removeFirst(pitchHistory.count - 400) }
    }

    private func pitch(after time: Double) -> Pitch? {
        pitchHistory.first { $0.time >= time + 0.03 && $0.time <= time + 0.3 }?.pitch
    }

    /// The analyser is made on the tap thread with the input's real sample rate.
    final class AnalyzerBox: @unchecked Sendable {
        let latency: Double
        private let lock = NSLock()
        private var analyzer: PlayCheckAnalyzer?
        init(latency: Double) { self.latency = latency }
        func feed(_ samples: [Float], _ host: UInt64, _ rate: Double) {
            let a: PlayCheckAnalyzer = lock.withLock {
                if let analyzer, analyzer.sampleRate == rate { return analyzer }
                let made = PlayCheckAnalyzer(sampleRate: rate, inputLatency: latency)
                analyzer = made
                return made
            }
            a.process(samples, hostTime: host)
        }
        var current: PlayCheckAnalyzer? { lock.withLock { analyzer } }
    }

    init() {
        let d = UserDefaults.standard
        settings = d.data(forKey: "playcheck.settings").flatMap { try? JSONDecoder().decode(Settings.self, from: $0) } ?? Settings()
        history = d.data(forKey: "playcheck.history").flatMap { try? JSONDecoder().decode([PlayAttempt].self, from: $0) } ?? []
    }

    // MARK: On / off

    func enable() async {
        guard let app, !isOn else { return }
        if app.audio.micPermission == .undetermined { _ = await app.audio.requestMicPermission() }
        guard app.audio.micPermission == .granted else {
            app.show("Нужен доступ к микрофону — Настройки → Truver", icon: .micOff, iconColor: Theme.sharp)
            return
        }
        try? app.audio.ensureRecording()
        #if os(iOS)
        speakerMode = app.audio.session.currentOutputName == "Динамик"
        let latency = app.audio.session.inputLatency
        #else
        speakerMode = false
        let latency = 0.0
        #endif
        let box = AnalyzerBox(latency: latency)
        self.box = box
        app.audio.host.onInputBlock = { samples, host, rate in box.feed(samples, host, rate) }
        isOn = true
        resetAttempt()
        adaptive = AdaptiveTempo(cleanBarsToStepUp: settings.cleanBars, ceiling: ceiling)
        // SM-9: a new session starts 10 % under the ceiling of this preset.
        if settings.adaptive, !app.metronome.isPlaying, let c = ceiling, app.metronome.state.modes.tempo == .none {
            let start = AdaptiveTempo.nextSessionStart(ceiling: c)
            if start < app.metronome.bpm {
                app.metronome.bpm = start
                app.show("Старт на 10 % ниже потолка \(Int(c)): \(Int(start))", icon: .metronome)
            }
        }
        // The input tap picks the observer up when it is installed.
        if app.tuner.isListening { app.tuner.handleAudioRestart() } else { app.updateListening() }
    }

    func disable() {
        guard let app, isOn else { return }
        finishAttempt()
        isOn = false
        app.audio.host.onInputBlock = nil
        box = nil
        if app.tuner.isListening { app.tuner.handleAudioRestart() }
        app.updateListening()
    }

    func toggle() {
        if isOn { disable() } else { Task { await enable() } }
    }

    private var ceilingKey: String { "playcheck.ceiling." + (app?.metronome.state.currentPresetId?.uuidString ?? "free") }
    var ceiling: Double? {
        let v = UserDefaults.standard.double(forKey: ceilingKey)
        return v > 0 ? v : nil
    }

    private func resetAttempt() {
        expected = []
        clickTimes = []
        clickStrength = nil
        recent = []
        lastBar = nil
        idle = false
        barStats = []
        allGraded = []
        gradingUnavailable = false
        attemptStart = nil
    }

    // MARK: Timeline in

    /// Every tick of the main track as it sounds (from the metronome's poll).
    func expect(_ tick: TimelineTick) {
        guard isOn else { return }
        let e = tick.event
        if attemptStart == nil {
            attemptStart = Date()
            startBPM = e.bpm
            adaptive = AdaptiveTempo(cleanBarsToStepUp: settings.cleanBars, ceiling: ceiling)
        }
        let time = PlayCheckAnalyzer.seconds(hostTime: tick.hostTime)
        if !e.isSilent { clickTimes.append(time); if clickTimes.count > 256 { clickTimes.removeFirst() } }
        if calibrating {
            if !e.isSilent && e.tick == 0 { calibrationClicks.append(time) }
            return
        }
        guard !e.isRest else { return }
        var pitch: Pitch?
        if let exercise {
            guard e.bar >= 1 else { return }   // bar 0 is the count-in
            let index = exerciseCounter % exercise.pitches.count
            exerciseCounter += 1
            pitch = exercise.pitches[index]
            exerciseIndexByTime[time] = index
            exercise.onNote(index)
        }
        expected.append(ExpectedNote(time: time, bar: e.bar, beat: e.beat, tick: e.tick,
                                     interval: 60 / e.bpm / Double(max(1, e.subdivision)), pitch: pitch, silentBar: e.isSilent))
    }

    /// Grades every bar the analyser has fully heard (called from the metronome's poll).
    func update() {
        guard isOn, let analyzer = box?.current, let heard = analyzer.heardUntil else { return }
        while let firstBar = expected.first?.bar {
            let notes = expected.filter { $0.bar == firstBar }
            guard let last = notes.last, last.time + last.interval / 2 + 0.08 < heard,
                  expected.contains(where: { $0.bar > firstBar }) else { return }
            expected.removeAll { $0.bar == firstBar }
            grade(notes, analyzer)
        }
    }

    private func grade(_ notes: [ExpectedNote], _ analyzer: PlayCheckAnalyzer) {
        guard let first = notes.first, let last = notes.last, let app else { return }
        if RhythmThresholds().bands(subdivision: first.interval) == nil { gradingUnavailable = true; return }
        gradingUnavailable = false
        // SM-6: the loop-measured residual of the microphone path moves every attack back onto the clicks' clock.
        let offset = routeOffset
        var onsets = analyzer.onsets(from: first.time - first.interval / 2 + offset, to: last.time + last.interval / 2 + offset)
            .map { TimedOnset(time: $0.time - offset, strength: $0.strength) }
        var masked: [Double] = []
        if speakerMode {
            // SM-7: the click reaches the microphone. Bar 0 (count-in) teaches the click's strength; later an attack
            // within 10 ms of a click that is not clearly louder is the click — that note is «не распознано»,
            // never a hit or a miss.
            let nearClick = onsets.filter { o in clickTimes.contains { abs($0 - o.time) <= 0.010 } }
            if first.bar == 0 {
                if !nearClick.isEmpty { clickStrength = nearClick.map(\.strength).sorted()[nearClick.count / 2] }
                return
            }
            if let clickStrength {
                let clicks = nearClick.filter { $0.strength < clickStrength * 1.6 }
                masked = clicks.map(\.time)
                onsets.removeAll { o in clicks.contains(o) }
            }
        }
        // Silence (found on the iPhone audit): a bar without a single attack is not «4 misses» — the player has
        // not started or has paused. It is neither graded nor counted for the tempo, the ceiling or the summary.
        guard !onsets.isEmpty else {   // through the speaker: only the click was heard
            idle = true
            return
        }
        idle = false
        let played = onsets.map { PlayedNote(time: $0.time, pitch: exercise == nil ? nil : pitch(after: $0.time)) }
        let graded = RhythmGrader.grade(expected: notes, played: played,
                                        pitchCheck: exercise == nil ? nil : PitchCheck(),
                                        isSounding: masked.isEmpty ? nil : { t in masked.contains { abs($0 - t) <= 0.012 } })
        if let exercise {
            for g in graded where g.wrongNote == true {
                if let t = g.expected?.time, let index = exerciseIndexByTime[t] { exercise.onWrong(index) }
            }
            for n in notes { exerciseIndexByTime[n.time] = nil }
        }
        allGraded += graded
        recent = Array((recent + graded.filter { $0.expected != nil }).suffix(16))
        guard let stats = RhythmStats.bars(graded).first else { return }
        lastBar = stats
        barStats.append(stats)
        guard settings.adaptive, app.metronome.state.modes.tempo == .none else { return }
        let tempo = app.metronome.bpm
        switch adaptive.record(stats, tempo: tempo) {
        case .stepUp:
            if let c = adaptive.ceiling { UserDefaults.standard.set(c, forKey: ceilingKey) }
            app.metronome.bpm = min(400, tempo + Double(settings.step))
            app.metronome.show(MetronomeToast(icon: .arrowUp, text: "\(settings.cleanBars) чистых такта — темп \(Int(app.metronome.bpm))"))
        case .stepDown:
            app.metronome.bpm = max(20, tempo - Double(settings.step))
            app.metronome.show(MetronomeToast(icon: .refresh, text: "Два такта меньше 70 % — темп \(Int(app.metronome.bpm))"))
        case .hold:
            break
        }
    }

    // MARK: Attempt summary (PL-3)

    /// The metronome stopped: the attempt ends (it continues if the metronome starts again while on).
    func metronomeStopped() {
        guard isOn else { return }
        finishAttempt()
        resetAttempt()
    }

    private func finishAttempt() {
        guard let app, let start = attemptStart else { return }
        let counted = barStats.filter(\.isCounted)
        guard counted.count >= 2 else { return }
        let deviations = allGraded.compactMap(\.deviation)
        let mean = deviations.isEmpty ? 0 : deviations.reduce(0, +) / Double(deviations.count)
        let spread = deviations.isEmpty ? 0 : (deviations.map { ($0 - mean) * ($0 - mean) }.reduce(0, +) / Double(deviations.count)).squareRoot()
        var perBeat: [Int: [Double]] = [:]
        for g in allGraded { if let e = g.expected, let d = g.deviation { perBeat[e.beat, default: []].append(d) } }
        let beatMeans = perBeat.mapValues { $0.reduce(0, +) / Double($0.count) * 1000 }
        let weakest = beatMeans.max { abs($0.value) < abs($1.value) }
        let attempt = PlayAttempt(date: Date(), preset: app.metronome.state.currentPreset?.name,
                                  seconds: Date().timeIntervalSince(start), startBPM: startBPM, endBPM: app.metronome.bpm,
                                  ceiling: adaptive.ceiling,
                                  accurateShare: counted.map(\.accurateShare).reduce(0, +) / Double(counted.count),
                                  meanDeviation: mean * 1000, spread: spread * 1000,
                                  weakestBeat: weakest?.key, weakestBeatDeviation: weakest?.value, bars: counted.count,
                                  silenceDrift: RhythmStats.silenceDrift(allGraded).map { $0 * 1000 }, perBeat: beatMeans)
        history.append(attempt)
        if history.count > 300 { history.removeFirst(history.count - 300) }
        if let data = try? JSONEncoder().encode(history) { UserDefaults.standard.set(data, forKey: "playcheck.history") }
        summary = attempt
        if !app.session.isRunning { app.sheet = .playCheckSummary }   // the session shows it in its own summary
    }

    #if DEBUG
    /// Screenshot hook: two weeks of attempts for the charts (not saved).
    func injectHistoryDemo() {
        let now = Date()
        var list: [PlayAttempt] = []
        for i in 0..<14 {
            let d = Double(i)
            let date = now.addingTimeInterval(-Double(13 - i) * 86_400)
            let beats: [Int: Double] = [0: -2, 1: 4, 2: -6, 3: -13, 4: 3, 5: 8, 6: -1]
            var a = PlayAttempt(date: date, preset: "Риф 7/8", seconds: 600, startBPM: 120, endBPM: 128 + d * 1.5,
                                ceiling: 126 + d * 1.6, accurateShare: 0.8, meanDeviation: -5, spread: 16 - d * 0.6,
                                weakestBeat: 3, weakestBeatDeviation: -12, bars: 40, silenceDrift: nil)
            a.perBeat = beats
            list.append(a)
        }
        history = list
    }

    /// Screenshot hook: a finished attempt.
    func injectDemo() {
        summary = PlayAttempt(date: Date(), preset: "Риф 7/8", seconds: 312, startBPM: 132, endBPM: 148, ceiling: 144,
                              accurateShare: 0.87, meanDeviation: -6.2, spread: 9.4, weakestBeat: 3, weakestBeatDeviation: -14,
                              bars: 46, silenceDrift: nil)
    }
    #endif
}
