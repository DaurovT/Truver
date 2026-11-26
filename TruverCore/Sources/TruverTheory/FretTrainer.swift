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

/// FB-12 «Тренажёр грифа»: a series of questions about notes on the neck. «Назови ноту» — a cell is shown, the
/// answer is a pitch class; «Сыграй ноту» — a note (optionally on a string) is named, the tuner hears the answer
/// (semitone accuracy, any octave — SM-5). Missed cells come back more often within the series.
public struct FretTrainer: Sendable {
    public enum Kind: String, Sendable, Codable, CaseIterable { case nameNote, playNote }

    public struct Options: Sendable, Codable, Equatable {
        /// Courses that may be asked (0 = lowest); empty — all.
        public var courses: [Int]
        public var frets: ClosedRange<Int>
        public var naturalsOnly: Bool
        public var count: Int
        /// «Повторить ошибки»: only cells of these pitch classes; nil — all.
        public var pitchClasses: [Int]?

        public init(courses: [Int] = [], frets: ClosedRange<Int> = 0...12, naturalsOnly: Bool = false, count: Int = 20,
                    pitchClasses: [Int]? = nil) {
            self.courses = courses
            self.frets = frets
            self.naturalsOnly = naturalsOnly
            self.count = max(1, count)
            self.pitchClasses = pitchClasses
        }
    }

    public struct Question: Sendable, Hashable {
        public var course: Int
        public var fret: Int
        public var pitch: Pitch
        public var pitchClass: Int { pitch.pitchClass }
    }

    public struct Answer: Sendable, Hashable {
        public var question: Question
        public var correct: Bool
        public var seconds: Double
    }

    public struct Summary: Sendable, Equatable {
        public var correct: Int
        public var total: Int
        public var averageSeconds: Double
        public var bestStreak: Int
        /// Courses with the most misses and slow answers, worst first (at most three).
        public var weakCourses: [Int]
        /// Pitch classes missed at least once, most missed first.
        public var missedPitchClasses: [Int]
    }

    public let kind: Kind
    public let options: Options
    public private(set) var answers: [Answer] = []
    public private(set) var current: Question?
    private let pool: [Question]
    private var missed: [Question] = []
    private var random: TrainerRandom

    public init(fretboard: Fretboard, kind: Kind, options: Options, seed: UInt64 = UInt64.random(in: 1...UInt64.max)) {
        self.kind = kind
        self.options = options
        random = TrainerRandom(seed: seed)
        let courses = options.courses.isEmpty ? Array(0..<fretboard.courseCount) : options.courses.filter { $0 < fretboard.courseCount }
        var pool: [Question] = []
        for course in courses {
            for fret in options.frets {
                guard let p = fretboard.pitch(course: course, fret: fret) else { continue }
                if options.naturalsOnly && [1, 3, 6, 8, 10].contains(p.pitchClass) { continue }
                if let only = options.pitchClasses, !only.isEmpty, !only.contains(p.pitchClass) { continue }
                pool.append(Question(course: course, fret: fret, pitch: p))
            }
        }
        self.pool = pool
    }

    public var isFinished: Bool { answers.count >= options.count || pool.isEmpty }
    public var number: Int { answers.count + 1 }

    /// The next question: never the same pitch class as the last one (a ringing note must not answer it); a missed
    /// cell comes back with a one-in-three chance.
    @discardableResult
    public mutating func next() -> Question? {
        guard !isFinished else { current = nil; return nil }
        let previous = current ?? answers.last?.question
        let candidates = pool.filter { $0.pitchClass != previous?.pitchClass }
        let retry = missed.filter { $0.pitchClass != previous?.pitchClass }
        if !retry.isEmpty && random.next() % 3 == 0 {
            current = retry[Int(random.next() % UInt64(retry.count))]
        } else {
            let list = candidates.isEmpty ? pool : candidates
            current = list[Int(random.next() % UInt64(list.count))]
        }
        return current
    }

    /// Records the answer to the current question; returns whether it was right.
    @discardableResult
    public mutating func answer(pitchClass: Int, seconds: Double) -> Bool {
        guard let q = current else { return false }
        let ok = ((pitchClass % 12) + 12) % 12 == q.pitchClass
        answers.append(Answer(question: q, correct: ok, seconds: seconds))
        if ok {
            if let i = missed.firstIndex(of: q) { missed.remove(at: i) }
        } else if !missed.contains(q) {
            missed.append(q)
        }
        current = nil
        return ok
    }

    /// «Пропустить»: counts as a miss.
    public mutating func skip(seconds: Double) {
        guard let q = current else { return }
        answer(pitchClass: q.pitchClass + 1, seconds: seconds)
    }

    public var summary: Summary {
        let correct = answers.filter(\.correct).count
        var best = 0, run = 0
        for a in answers { run = a.correct ? run + 1 : 0; best = max(best, run) }
        let average = answers.isEmpty ? 0 : answers.map(\.seconds).reduce(0, +) / Double(answers.count)
        // Weakness score per course: a miss counts as 3 s on top of the time.
        var score: [Int: (Double, Int)] = [:]
        for a in answers {
            let s = a.seconds + (a.correct ? 0 : 3)
            let old = score[a.question.course] ?? (0, 0)
            score[a.question.course] = (old.0 + s, old.1 + 1)
        }
        let averages = score.mapValues { $0.0 / Double($0.1) }
        let overall = averages.values.reduce(0, +) / Double(max(1, averages.count))
        let weak = averages.filter { $0.value > overall * 1.15 }.sorted { $0.value > $1.value }.prefix(3).map(\.key)
        var misses: [Int: Int] = [:]
        for a in answers where !a.correct { misses[a.question.pitchClass, default: 0] += 1 }
        let missedClasses = misses.sorted { $0.value == $1.value ? $0.key < $1.key : $0.value > $1.value }.map(\.key)
        return Summary(correct: correct, total: answers.count, averageSeconds: average, bestStreak: best,
                       weakCourses: Array(weak), missedPitchClasses: missedClasses)
    }
}

/// SplitMix64 — reproducible series in tests.
struct TrainerRandom: Sendable {
    private var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
