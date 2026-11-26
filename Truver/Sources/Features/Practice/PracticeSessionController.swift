import AVFoundation
import Foundation
import Observation
import TruverDSP

/// PL-1 exercise: a metronome preset (or the current settings), how long, with the play check or on the neck.
struct PracticeStep: Codable, Identifiable, Equatable {
    var id = UUID()
    /// Metronome preset; nil — the settings that are on the metronome when the step starts.
    var presetId: UUID?
    var minutes = 5
    /// Stage SM «Проверка игры» on the metronome.
    var check = true
    /// FB-14: the current scale position on the neck, played and checked note by note.
    var onNeck = false
}

/// PL-2 plan: exercises in order, a pause between them, voice prompts.
struct PracticePlan: Codable, Equatable {
    var steps: [PracticeStep] = [PracticeStep()]
    var pauseSeconds = 20
    var voice = true
}

/// PL-2 «Занятие»: runs the plan — the exercise with its timer, the pause with a spoken prompt, the summary.
@MainActor
@Observable
final class PracticeSessionController {
    weak var app: AppModel?

    enum Phase: Equatable { case idle, playing, pause, done }

    struct StepResult: Identifiable, Equatable {
        var id = UUID()
        var title: String
        var seconds: Double
        var attempt: PlayAttempt?
    }

    var plan: PracticePlan {
        didSet { if let data = try? JSONEncoder().encode(plan) { UserDefaults.standard.set(data, forKey: "practice.plan") } }
    }
    private(set) var phase: Phase = .idle
    private(set) var stepIndex = 0
    private(set) var remaining: Double = 0
    private(set) var results: [StepResult] = []
    /// Length of the running phase (the exercise or the pause), s — the ring's full circle.
    private(set) var phaseLength: Double = 0
    /// The big «Пауза» button of the running screen: the timer and the metronome hold.
    private(set) var isPaused = false
    /// While a session runs the play check's own summary sheet does not pop up between steps.
    var isRunning: Bool { phase == .playing || phase == .pause }

    private var timer: Task<Void, Never>?
    private var stepStart = Date()
    private let speech = AVSpeechSynthesizer()

    init() {
        plan = UserDefaults.standard.data(forKey: "practice.plan").flatMap { try? JSONDecoder().decode(PracticePlan.self, from: $0) } ?? PracticePlan()
    }

    func title(_ step: PracticeStep) -> String {
        guard let app else { return "Упражнение" }
        let preset = step.presetId.flatMap { id in app.metronome.state.presets.first { $0.id == id } }
        let base = preset?.name ?? "Текущие настройки"
        return step.onNeck ? base + " · " + app.fretboard.scaleTitle : base
    }

    var currentStep: PracticeStep? { plan.steps[safe: stepIndex] }
    var nextStep: PracticeStep? { plan.steps[safe: stepIndex + 1] }

    // MARK: Run

    func start() {
        guard !plan.steps.isEmpty else { return }
        results = []
        stepIndex = 0
        say("Начинаем. \(title(plan.steps[0])), \(plan.steps[0].minutes) \(Self.minutes(plan.steps[0].minutes)).")
        beginStep()
    }

    func stop() {
        timer?.cancel()
        isPaused = false
        if phase == .playing { endStep(advance: false) }
        phase = results.isEmpty ? .idle : .done
    }

    func skip() {
        guard phase == .playing || phase == .pause else { return }
        timer?.cancel()
        isPaused = false
        if phase == .playing { endStep(advance: true) } else { beginStep() }
    }

    func reset() { phase = .idle; results = []; isPaused = false }

    /// Holds the timer and the metronome; `resume` goes on from the same second.
    func pause() {
        guard phase == .playing || phase == .pause, !isPaused, let app else { return }
        isPaused = true
        timer?.cancel()
        if phase == .playing, app.metronome.isPlaying { app.metronome.stop() }
    }

    func resume() {
        guard isPaused, let app else { return }
        isPaused = false
        if phase == .playing, currentStep?.onNeck == false, !app.metronome.isPlaying { app.metronome.start() }
        runTimer()
    }

    func togglePause() { isPaused ? resume() : pause() }

    private func beginStep() {
        guard let app, let step = currentStep else { finish(); return }
        phase = .playing
        isPaused = false
        stepStart = Date()
        remaining = Double(step.minutes) * 60
        phaseLength = remaining
        if let id = step.presetId, let preset = app.metronome.state.presets.first(where: { $0.id == id }) {
            app.metronome.load(preset)
        }
        if step.onNeck {
            app.fretboard.startTraining()
        } else if step.check {
            Task {
                await app.playCheck.enable()
                if !app.metronome.isPlaying { app.metronome.start() }
            }
        } else if !app.metronome.isPlaying {
            app.metronome.start()
        }
        runTimer()
    }

    private func runTimer() {
        timer?.cancel()
        timer = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard let self, !Task.isCancelled else { return }
                self.remaining -= 1
                if self.remaining <= 0 {
                    if self.phase == .playing { self.endStep(advance: true) } else { self.beginStep() }
                    return
                }
            }
        }
    }

    private func endStep(advance: Bool) {
        guard let app, let step = currentStep else { return }
        if step.onNeck { app.fretboard.stopTraining() } else { app.metronome.stop(); if app.playCheck.isOn { app.playCheck.disable() } }
        let attempt = app.playCheck.summary.flatMap { $0.date >= stepStart ? $0 : nil }
        results.append(StepResult(title: title(step), seconds: Date().timeIntervalSince(stepStart), attempt: attempt))
        if app.sheet == .playCheckSummary { app.sheet = nil }
        guard advance else { return }
        stepIndex += 1
        guard let next = currentStep else { finish(); return }
        phase = .pause
        remaining = Double(plan.pauseSeconds)
        phaseLength = remaining
        say("Пауза \(plan.pauseSeconds) секунд. Дальше — \(title(next)), \(next.minutes) \(Self.minutes(next.minutes)).")
        if plan.pauseSeconds <= 0 { beginStep() } else { runTimer() }
    }

    private func finish() {
        timer?.cancel()
        phase = .done
        say("Занятие закончено.")
    }

    private func say(_ text: String) {
        guard plan.voice else { return }
        let u = AVSpeechUtterance(string: text)
        u.voice = AVSpeechSynthesisVoice(language: "ru-RU")
        u.rate = 0.52
        speech.stopSpeaking(at: .immediate)
        speech.speak(u)
    }

    /// «100 BPM · 4/4» of a step: its preset's tempo and meter, or the metronome's current ones.
    func tempoText(_ step: PracticeStep) -> String {
        guard let app else { return "" }
        let preset = step.presetId.flatMap { id in app.metronome.state.presets.first { $0.id == id } }
        let meter = preset?.settings ?? app.metronome.meter
        return "\(Int(meter.bpm.rounded())) BPM · \(meter.numerator)/\(meter.denominator)"
    }

    /// Screenshot hook `-sessionRunning`: the plan starts and stands 3 s in (4:57 of 5:00), the timer held.
    func debugRunning() {
        plan.voice = false
        start()
        timer?.cancel()
        remaining -= 3
        demoShare = 0.92
    }

    /// Screenshot value of the play-check chip (the simulator hears no playing).
    private(set) var demoShare: Double?
    private static var debugApplied = false

    /// Launch arguments of the session boards, once: `-sessionRunning`.
    func applyDebugArguments() {
        guard !Self.debugApplied else { return }
        Self.debugApplied = true
        if ProcessInfo.processInfo.arguments.contains("-sessionRunning"), phase == .idle { debugRunning() }
    }

    static func minutes(_ n: Int) -> String { ModeParamsSheet.plural(n, "минута", "минуты", "минут") }
}
