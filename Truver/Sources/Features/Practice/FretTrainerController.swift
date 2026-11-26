import Foundation
import Observation
import TruverDSP
import TruverTheory

/// FB-12 state: the series, timing, feedback and — for «Сыграй ноту» — the tuner's readings (chromatic mode while
/// the trainer is open; the microphone is on only then, AU-4).
@MainActor
@Observable
final class FretTrainerController {
    weak var app: AppModel?

    enum Feedback: Equatable { case none, correct, wrong(expected: Int, heard: Int?) }

    struct Settings: Codable, Equatable {
        enum Strings: String, Codable, CaseIterable { case all, low, high }
        enum Frets: String, Codable, CaseIterable { case first12, whole, upper }
        var kind: FretTrainer.Kind = .nameNote
        var strings: Strings = .all
        var frets: Frets = .first12
        var naturalsOnly = false
        var count = 20
        var showString = true
    }

    struct LastResult: Codable, Equatable {
        var correct: Int
        var total: Int
        var averageSeconds: Double
        var kind: FretTrainer.Kind
    }

    var settings: Settings {
        didSet {
            if let data = try? JSONEncoder().encode(settings) { UserDefaults.standard.set(data, forKey: "trainer.settings") }
        }
    }
    private(set) var lastResult: LastResult?
    private(set) var session: FretTrainer?
    private(set) var feedback: Feedback = .none
    private(set) var isOpen = false
    /// «Слышу F♯» while playing.
    private(set) var heard: Int?
    /// Seconds the last answer took (the «Верно» card: «0,8 с»).
    private(set) var answerSeconds: Double = 0
    /// «Подсказка» in «Сыграй ноту»: the asked cell is shown.
    private(set) var hintShown = false
    /// The series summary to show (`-trainerSummary` puts the canvas example here).
    private(set) var demoSummary: SummaryInfo?

    /// What the summary screen shows (the series' summary or the screenshot example).
    struct SummaryInfo: Equatable {
        var correct: Int
        var total: Int
        var averageSeconds: Double
        var bestStreak: Int
        var weakCourses: [Int]
        var missedPitchClasses: [Int]
        var kind: FretTrainer.Kind
        var frets: ClosedRange<Int>
    }

    var summaryInfo: SummaryInfo? {
        if let demoSummary { return demoSummary }
        guard isFinished, let s = session else { return nil }
        let sum = s.summary
        return SummaryInfo(correct: sum.correct, total: sum.total, averageSeconds: sum.averageSeconds, bestStreak: sum.bestStreak,
                           weakCourses: sum.weakCourses, missedPitchClasses: sum.missedPitchClasses, kind: s.kind, frets: s.options.frets)
    }

    private var askedAt = Date()
    private var listenFrom = Date()
    private var stableClass: Int?
    private var stableCount = 0
    private var wrongCount = 0
    private var advanceTask: Task<Void, Never>?
    private var modeBefore: TunerController.Mode?

    init() {
        let d = UserDefaults.standard
        settings = d.data(forKey: "trainer.settings").flatMap { try? JSONDecoder().decode(Settings.self, from: $0) } ?? Settings()
        lastResult = d.data(forKey: "trainer.last").flatMap { try? JSONDecoder().decode(LastResult.self, from: $0) }
    }

    /// The question on screen: stays while the answer's feedback shows (the session has moved on by then).
    private(set) var question: FretTrainer.Question?
    var isFinished: Bool { session?.isFinished ?? false }

    // MARK: Open / close

    func open() {
        isOpen = true
        newSeries()
        applyDebugArguments()
    }

    func close() {
        advanceTask?.cancel()
        isOpen = false
        session = nil
        question = nil
        demoSummary = nil
        updateListening()
    }

    func newSeries() { newSeries(only: nil) }

    /// «Повторить ошибки»: a series of the missed notes only.
    func repeatMistakes() {
        guard let missed = summaryInfo?.missedPitchClasses, !missed.isEmpty else { return }
        newSeries(only: missed)
    }

    private func newSeries(only pitchClasses: [Int]?) {
        guard let app, let board = Fretboard(instrument: app.instrument) else { return }
        advanceTask?.cancel()
        demoSummary = nil
        let n = board.courseCount
        let courses: [Int]
        switch settings.strings {
        case .all: courses = []
        case .low: courses = Array(0..<min(3, n))
        case .high: courses = Array(max(0, n - 3)..<n)
        }
        let top = app.instrument.fretCount
        let frets: ClosedRange<Int>
        switch settings.frets {
        case .first12: frets = 0...min(12, top)
        case .whole: frets = 0...top
        case .upper: frets = min(12, top)...top
        }
        let options = FretTrainer.Options(courses: courses, frets: frets, naturalsOnly: settings.naturalsOnly, count: settings.count,
                                          pitchClasses: pitchClasses)
        session = FretTrainer(fretboard: board, kind: settings.kind, options: options, seed: Self.debugSeed ?? UInt64.random(in: 1...UInt64.max))
        Self.debugSeed = nil
        feedback = .none
        ask()
        updateListening()
    }

    private func ask() {
        question = session?.next()
        askedAt = Date()
        // A ringing previous note must not answer the new question.
        listenFrom = Date().addingTimeInterval(0.45)
        stableClass = nil
        stableCount = 0
        wrongCount = 0
        heard = nil
        hintShown = false
        if session?.isFinished == true { finish() }
    }

    /// The tuner listens while «Сыграй ноту» is open (chromatic: any note gives a reading).
    private func updateListening() {
        guard let app else { return }
        let needs = isOpen && settings.kind == .playNote && !isFinished
        if needs {
            app.fretboard.stopDrone()   // 6.1 п. 5: no drone through the speaker while notes are checked
            if modeBefore == nil { modeBefore = app.tuner.mode }
            if app.tuner.mode != .chromatic { app.tuner.mode = .chromatic }
        } else if let previous = modeBefore {
            app.tuner.mode = previous
            modeBefore = nil
        }
        app.updateListening()
    }

    var needsMicrophone: Bool { isOpen && settings.kind == .playNote && !isFinished }

    // MARK: Answers

    func answer(pitchClass: Int) {
        guard var s = session, let q = s.current, feedback == .none else { return }
        let seconds = Date().timeIntervalSince(askedAt)
        question = q
        let ok = s.answer(pitchClass: pitchClass, seconds: seconds)
        session = s
        answerSeconds = seconds
        app?.practice.activity(tuned: false)
        feedback = ok ? .correct : .wrong(expected: q.pitchClass, heard: pitchClass)
        advanceTask?.cancel()
        // Canvas: right — on by itself in a second; wrong — by «Дальше», to have time to read why.
        guard ok, !Self.holdFeedback else { return }
        advanceTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled, let self else { return }
            self.next()
        }
    }

    /// «Дальше» after a wrong answer (and the end of a right one).
    func next() {
        advanceTask?.cancel()
        guard feedback != .none else { return }
        feedback = .none
        ask()
    }

    func showHint() { hintShown = true }

    func skip() {
        guard var s = session, let q = s.current, feedback == .none else { return }
        s.skip(seconds: Date().timeIntervalSince(askedAt))
        session = s
        feedback = .wrong(expected: q.pitchClass, heard: nil)
        advanceTask?.cancel()
    }

    /// «Сыграй ноту»: three steady readings of one pitch class decide; a wrong note is named first and counts only
    /// if it stays (a slide or a neighbour string rings briefly).
    func hear(_ reading: TunerReading) {
        guard isOpen, settings.kind == .playNote, feedback == .none, let q = question, Date() >= listenFrom,
              !reading.isProvisional else { return }
        let pc = reading.pitch.pitchClass
        if pc == stableClass { stableCount += 1 } else { stableClass = pc; stableCount = 1 }
        heard = pc
        if pc == q.pitchClass && stableCount >= 3 {
            answer(pitchClass: pc)
        } else if pc != q.pitchClass && stableCount >= 16 {   // 0.4 s: a slide or a neighbour string is not a mistake
            answer(pitchClass: pc)
        }
    }

    // MARK: Screenshot hooks

    /// Seed of the next series (screenshots: the question the board asks).
    static var debugSeed: UInt64?
    /// Keeps the «Верно» state on screen (screenshots).
    static var holdFeedback = false
    private static var debugApplied = false

    /// Launch arguments of the trainer boards, once: `-trainerAsk course:fret` (that question after
    /// `-trainerPrior N` right answers), `-trainerRight` (answered right in 0.8 s), `-trainerWrong pc` (answered
    /// with that pitch class), `-trainerSummary` (the canvas summary).
    private func applyDebugArguments() {
        guard !Self.debugApplied, let app else { return }
        Self.debugApplied = true
        let args = ProcessInfo.processInfo.arguments
        func value(_ key: String) -> String? { args.firstIndex(of: key).flatMap { $0 + 1 < args.count ? args[$0 + 1] : nil } }
        if args.contains("-trainerSummary") {
            demoSummary = SummaryInfo(correct: 1, total: 20, averageSeconds: 1.9, bestStreak: 1,
                                      weakCourses: [max(0, app.instrument.courses.count - 2)], missedPitchClasses: [1, 11, 4, 5, 6, 7, 8],
                                      kind: .nameNote, frets: 6...10)
            updateListening()
            return
        }
        guard let ask = value("-trainerAsk"), let board = Fretboard(instrument: app.instrument) else { return }
        let parts = ask.split(separator: ":").compactMap { Int($0) }
        guard parts.count == 2, let s0 = session else { return }
        let prior = value("-trainerPrior").flatMap(Int.init) ?? 0
        for seed in UInt64(1)...200_000 {
            var t = FretTrainer(fretboard: board, kind: s0.kind, options: s0.options, seed: seed)
            for _ in 0..<prior { if let q = t.next() { t.answer(pitchClass: q.pitchClass, seconds: 1.2) } }
            guard let q = t.next(), q.course == parts[0], q.fret == parts[1] else { continue }
            var series = FretTrainer(fretboard: board, kind: s0.kind, options: s0.options, seed: seed)
            for _ in 0..<prior { if let p = series.next() { series.answer(pitchClass: p.pitchClass, seconds: 1.2) } }
            question = series.next()
            session = series
            askedAt = Date()
            // A screenshot: the simulator's microphone hears the room, the board shows «Слушаю…».
            listenFrom = .distantFuture
            break
        }
        if args.contains("-trainerRight"), let q = question {
            Self.holdFeedback = true
            askedAt = Date().addingTimeInterval(-0.8)
            answer(pitchClass: q.pitchClass)
            answerSeconds = 0.8
        } else if let pc = value("-trainerWrong").flatMap(Int.init) {
            answer(pitchClass: pc)
        }
    }

    private func finish() {
        guard let s = session else { return }
        let sum = s.summary
        let result = LastResult(correct: sum.correct, total: sum.total, averageSeconds: sum.averageSeconds, kind: s.kind)
        lastResult = result
        if let data = try? JSONEncoder().encode(result) { UserDefaults.standard.set(data, forKey: "trainer.last") }
        updateListening()
    }
}
