#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif
import TruverDSP
import TruverTheory

/// Bridge commands of the Practice feature (Flutter: lib/features/practice/). Method names: "practice.<name>".
///
/// FB-12 «Тренажёр грифа»: the series lives here (`FretTrainer` of the core — question generation, retries of
/// missed cells, the summary); the Dart `FretTrainerController` keeps only timing, feedback and listening, as
/// `FretTrainerController.swift` does around the same struct.
extension Bridge {
    func registerPractice() {
        /// `FretTrainerController.newSeries`: a new series on the current instrument. `frets`: [low, high].
        struct StartParams: Decodable {
            var kind: FretTrainer.Kind
            var courses: [Int]
            var frets: [Int]
            var naturalsOnly: Bool
            var count: Int
            var seed: UInt64?
            /// «Повторить ошибки»: only these pitch classes.
            var pitchClasses: [Int]?
        }
        register("practice.trainerStart", StartParams.self) { [unowned self] p in
            guard let board = Fretboard(instrument: instrument) else { throw BridgeError("no fretboard") }
            let low = p.frets.first ?? 0, high = max(low, p.frets.last ?? low)
            let options = FretTrainer.Options(courses: p.courses, frets: low...high, naturalsOnly: p.naturalsOnly, count: p.count,
                                              pitchClasses: p.pitchClasses)
            PracticeState.shared.trainer = p.seed.map { FretTrainer(fretboard: board, kind: p.kind, options: options, seed: $0) }
                ?? FretTrainer(fretboard: board, kind: p.kind, options: options)
            return try trainerState()
        }

        /// `session.next()`: the next question (nil once the series is finished).
        register("practice.trainerNext") { [unowned self] _ in
            guard PracticeState.shared.trainer != nil else { throw BridgeError("no series") }
            PracticeState.shared.trainer?.next()
            return try trainerState()
        }

        struct AnswerParams: Decodable { var pitchClass: Int; var seconds: Double }
        struct AnswerResult: Encodable { var correct: Bool; var state: TrainerStateDTO }
        register("practice.trainerAnswer", AnswerParams.self) { [unowned self] p in
            guard PracticeState.shared.trainer != nil else { throw BridgeError("no series") }
            let ok = PracticeState.shared.trainer?.answer(pitchClass: p.pitchClass, seconds: p.seconds) ?? false
            return AnswerResult(correct: ok, state: try trainerState())
        }

        struct SkipParams: Decodable { var seconds: Double }
        register("practice.trainerSkip", SkipParams.self) { [unowned self] p in
            guard PracticeState.shared.trainer != nil else { throw BridgeError("no series") }
            PracticeState.shared.trainer?.skip(seconds: p.seconds)
            return try trainerState()
        }

        register("practice.trainerState") { [unowned self] _ in try trainerState() }

        /// Screenshot hook (`-trainerAsk course:fret -trainerPrior N`): the seed whose series, after N right answers,
        /// asks this cell next. Same options as `practice.trainerStart`.
        struct FindParams: Decodable {
            var kind: FretTrainer.Kind
            var courses: [Int]
            var frets: [Int]
            var naturalsOnly: Bool
            var count: Int
            var course: Int
            var fret: Int
            var prior: Int
        }
        struct Seed: Encodable { var seed: UInt64? }
        register("practice.trainerFindSeed", FindParams.self) { [unowned self] p in
            guard let board = Fretboard(instrument: instrument) else { throw BridgeError("no fretboard") }
            let low = p.frets.first ?? 0, high = max(low, p.frets.last ?? low)
            let options = FretTrainer.Options(courses: p.courses, frets: low...high, naturalsOnly: p.naturalsOnly, count: p.count)
            for seed in UInt64(1)...200_000 {
                var t = FretTrainer(fretboard: board, kind: p.kind, options: options, seed: seed)
                for _ in 0..<p.prior { if let q = t.next() { t.answer(pitchClass: q.pitchClass, seconds: 1.2) } }
                if let q = t.next(), q.course == p.course, q.fret == p.fret { return Seed(seed: seed) }
            }
            return Seed(seed: nil)
        }

        /// Open-string names of the current tuning without the octave («F♯», «B»…; the trainer's «5-й струне (A)»).
        struct OpenNames: Encodable { var names: [String] }
        register("practice.openNames") { [unowned self] _ in
            let f = formatter
            return OpenNames(names: tuning.spelledNotes.map { f.string($0.name) })
        }

        register("practice.trainerEnd") { _ in
            PracticeState.shared.trainer = nil
            return Done()
        }

        /// Note names of the 12 pitch classes in the app's notation: `simpleSpelling(preferFlats: false / true)`
        /// (the trainer's buttons and texts: «F♯», small «G♭» under it).
        struct NoteNames: Encodable { var sharps: [String]; var flats: [String] }
        register("practice.noteNames") { [unowned self] _ in
            let f = formatter
            return NoteNames(sharps: (0..<12).map { f.string(NoteName.simpleSpelling(ofPitchClass: $0, preferFlats: false)) },
                             flats: (0..<12).map { f.string(NoteName.simpleSpelling(ofPitchClass: $0, preferFlats: true)) })
        }
    }

    fileprivate func trainerState() throws -> TrainerStateDTO {
        guard let t = PracticeState.shared.trainer else { throw BridgeError("no series") }
        let s = t.summary
        return TrainerStateDTO(
            kind: t.kind, count: t.options.count, naturalsOnly: t.options.naturalsOnly,
            answered: t.answers.count, correct: t.answers.filter(\.correct).count, isFinished: t.isFinished,
            current: t.current.map { q in
                QuestionDTO(course: q.course, fret: q.fret, pitchClass: q.pitchClass, cents: q.pitch.cents,
                            fullName: formatter.string(SpelledNote(NoteName.simpleSpelling(ofPitchClass: q.pitchClass, preferFlats: false),
                                                                   midi: q.pitch.nearestMIDI)))
            },
            frets: [t.options.frets.lowerBound, t.options.frets.upperBound],
            summary: SummaryDTO(correct: s.correct, total: s.total, averageSeconds: s.averageSeconds, bestStreak: s.bestStreak,
                                weakCourses: s.weakCourses, missedPitchClasses: s.missedPitchClasses))
    }
}

struct QuestionDTO: Encodable {
    var course: Int
    var fret: Int
    var pitchClass: Int
    var cents: Double
    /// With the octave («D3»): the «Верно · D3» card.
    var fullName: String
}

struct SummaryDTO: Encodable {
    var correct: Int
    var total: Int
    var averageSeconds: Double
    var bestStreak: Int
    var weakCourses: [Int]
    var missedPitchClasses: [Int]
}

struct TrainerStateDTO: Encodable {
    var kind: FretTrainer.Kind
    var count: Int
    var naturalsOnly: Bool
    var answered: Int
    var correct: Int
    var isFinished: Bool
    var current: QuestionDTO?
    /// `options.frets` as [low, high].
    var frets: [Int]
    var summary: SummaryDTO
}

/// The running trainer series (guarded by the bridge lock: every `call` holds it).
final class PracticeState: @unchecked Sendable {
    static let shared = PracticeState()
    var trainer: FretTrainer?
}
