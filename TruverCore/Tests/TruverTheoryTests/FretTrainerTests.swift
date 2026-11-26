import Foundation
import Testing
@testable import TruverTheory

@Suite("Fretboard trainer (FB-12)")
struct FretTrainerTests {
    let board = Fretboard(instrument: TuningTemplates.template(id: "g8-standard-fs")!.makeInstrument())!

    @Test("Questions stay in the chosen strings and frets; no pitch class twice in a row; the series ends")
    func questions() {
        var t = FretTrainer(fretboard: board, kind: .nameNote,
                            options: .init(courses: [0, 1, 2], frets: 0...5, naturalsOnly: true, count: 30), seed: 7)
        var last: Int?
        while let q = t.next() {
            #expect([0, 1, 2].contains(q.course) && (0...5).contains(q.fret))
            #expect(![1, 3, 6, 8, 10].contains(q.pitchClass))
            #expect(q.pitchClass != last)
            #expect(board.pitch(course: q.course, fret: q.fret) == q.pitch)
            last = q.pitchClass
            t.answer(pitchClass: q.pitchClass, seconds: 1)
        }
        #expect(t.isFinished && t.answers.count == 30)
    }

    @Test("Answers in any octave count; misses come back; summary names the weak string")
    func summary() {
        var t = FretTrainer(fretboard: board, kind: .playNote, options: .init(count: 40), seed: 3)
        while let q = t.next() {
            // Always slow and wrong on the lowest string, quick and right elsewhere.
            if q.course == 0 { t.answer(pitchClass: q.pitchClass + 1, seconds: 4) } else { t.answer(pitchClass: q.pitchClass + 24, seconds: 1) }
        }
        let s = t.summary
        #expect(s.total == 40)
        #expect(s.correct == t.answers.filter { $0.question.course != 0 }.count)
        #expect(s.weakCourses.first == 0)
        #expect(!s.missedPitchClasses.isEmpty)
        // A missed cell is asked again: some question repeats.
        let missed = Set(t.answers.filter { !$0.correct }.map(\.question))
        #expect(t.answers.filter { missed.contains($0.question) }.count > missed.count)
    }
}
