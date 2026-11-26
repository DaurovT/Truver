import Foundation
import Testing
@testable import TruverDSP
@testable import TruverTheory

@Suite("Smart mode grading (SM-2…SM-5, SM-8, SM-9)")
struct RhythmTests {
    let thresholds = RhythmThresholds()

    @Test("SM-4 bands: the PRD's two examples")
    func bandsExamples() throws {
        let slow = try #require(thresholds.bands(subdivision: 1.0))       // 1/4 at 60 BPM
        #expect(slow.exact == 0.010 && slow.good == 0.025 && slow.inaccurate == 0.050 && slow.half == 0.5)
        let fast = try #require(thresholds.bands(subdivision: 0.075))     // 1/16 at 200 BPM
        #expect(abs(fast.exact - 0.006) < 1e-9)
        #expect(abs(fast.good - 0.015) < 1e-9)
        #expect(abs(fast.inaccurate - 0.02625) < 1e-9)
        #expect(abs(fast.half - 0.0375) < 1e-9)
    }

    @Test("SM-4 bands are monotonic for every gradable subdivision; below 40 ms there is no grading")
    func bandsMonotonic() {
        for ms in stride(from: 40.0, through: 1500, by: 0.5) {
            guard let b = thresholds.bands(subdivision: ms / 1000) else { Issue.record("no bands at \(ms)"); continue }
            #expect(b.exact <= b.good && b.good <= b.inaccurate && b.inaccurate <= b.half, "\(ms) ms")
        }
        #expect(thresholds.bands(subdivision: 0.039) == nil)
    }

    func grid(beats: Int, interval: Double, bars beatsPerBar: Int = 4, start: Double = 1) -> [ExpectedNote] {
        (0..<beats).map { i in ExpectedNote(time: start + Double(i) * interval, bar: i / beatsPerBar, beat: i % beatsPerBar, interval: interval) }
    }

    @Test("SM-2: binding, extra attacks, missing notes, the closest attack wins")
    func binding() {
        let expected = grid(beats: 4, interval: 0.5)   // 1.0, 1.5, 2.0, 2.5
        let played = [PlayedNote(time: 1.004),          // exact
                      PlayedNote(time: 1.52),           // good
                      PlayedNote(time: 1.53),           // second claim on 1.5 → extra
                      PlayedNote(time: 1.76),           // farther than half from both → extra? (1.75 is the middle) yes
                      PlayedNote(time: 2.04)]           // inaccurate
        let graded = RhythmGrader.grade(expected: expected, played: played)
        let byTime = Dictionary(uniqueKeysWithValues: graded.compactMap { g in g.expected.map { ($0.time, g.grade) } })
        #expect(byTime[1.0] == .exact)
        #expect(byTime[1.5] == .good)
        #expect(byTime[2.0] == .inaccurate)
        #expect(byTime[2.5] == .missing)
        #expect(graded.filter { $0.grade == .extra }.count == 2)
        #expect(abs((graded.first { $0.expected?.time == 1.0 }?.deviation ?? 0) - 0.004) < 1e-9)
    }

    @Test("SM-10: no attack but sound present → unrecognized, not missing")
    func unrecognized() {
        let expected = grid(beats: 2, interval: 0.5)
        let graded = RhythmGrader.grade(expected: expected, played: [PlayedNote(time: 1.0)], isSounding: { _ in true })
        #expect(graded.map(\.grade) == [.exact, .unrecognized])
    }

    @Test("SM-5: wrong note within a semitone tolerance; any octave if allowed")
    func pitchCheck() {
        let a2 = SpelledNote(parsing: "A2")!.pitch, a3 = SpelledNote(parsing: "A3")!.pitch, b2 = SpelledNote(parsing: "B2")!.pitch
        var expected = grid(beats: 3, interval: 0.5)
        for i in expected.indices { expected[i].pitch = a2 }
        let played = [PlayedNote(time: 1.0, pitch: a2.transposed(byCents: 30)), PlayedNote(time: 1.5, pitch: b2), PlayedNote(time: 2.0, pitch: a3)]
        let strict = RhythmGrader.grade(expected: expected, played: played, pitchCheck: PitchCheck())
        #expect(strict.map(\.wrongNote) == [false, true, true])
        let loose = RhythmGrader.grade(expected: expected, played: played, pitchCheck: PitchCheck(anyOctave: true))
        #expect(loose.map(\.wrongNote) == [false, true, false])
    }

    @Test("SM-3 bar stats and SM-8 counting rule")
    func barStats() throws {
        let expected = grid(beats: 8, interval: 0.25)
        let played = [0.995, 1.255, 1.497, 1.758, 2.0, 2.27, 2.5].map { PlayedNote(time: $0) }   // bar 1 last note missing
        let graded = RhythmGrader.grade(expected: expected, played: played)
        let bars = RhythmStats.bars(graded)
        #expect(bars.count == 2)
        let first = bars[0]
        #expect(first.accurateShare == 1)
        #expect(first.missing == 0)
        #expect(abs((first.meanDeviation ?? 0) - 0.00125) < 1e-9)
        let second = bars[1]
        #expect(second.missing == 1)
        #expect(second.accurateShare == 0.75)    // exact, good (20 ms ≤ 25 ms), exact, missing
        #expect(second.isCounted)

        let noisy = RhythmGrader.grade(expected: grid(beats: 4, interval: 0.25), played: [PlayedNote(time: 1.0)], isSounding: { _ in true })
        #expect(RhythmStats.bars(noisy)[0].isCounted == false)   // 3 of 4 unrecognized
    }

    @Test("SM-8: N clean bars → up; 2 bars under 70 % → down; uncounted bars do not count; SM-9 ceiling")
    func adaptive() {
        func bar(_ share: Double, counted: Bool = true, missing: Int = 0) -> BarStats {
            BarStats(bar: 0, meanDeviation: 0, spread: 0, accurateShare: share, graded: 8, missing: missing, extra: 0,
                     wrongNotes: 0, unrecognizedShare: counted ? 0 : 0.5, isCounted: counted, perBeat: [:])
        }
        var tempo = AdaptiveTempo(cleanBarsToStepUp: 3)
        #expect(tempo.record(bar(1), tempo: 100) == .hold)
        #expect(tempo.record(bar(0.95), tempo: 100) == .hold)
        #expect(tempo.record(bar(0.5, counted: false), tempo: 100) == .hold)   // skipped, the run continues
        #expect(tempo.record(bar(0.92), tempo: 100) == .stepUp)
        #expect(tempo.ceiling == 100)
        #expect(tempo.record(bar(0.95, missing: 1), tempo: 105) == .hold)     // a missing note is not clean
        #expect(tempo.record(bar(0.6), tempo: 105) == .hold)
        #expect(tempo.record(bar(0.65), tempo: 105) == .stepDown)
        #expect(AdaptiveTempo.nextSessionStart(ceiling: 140) == 126)
    }

    @Test("SM-3: drift over the silent bars")
    func drift() {
        var expected = grid(beats: 12, interval: 0.5)
        for i in 4..<8 { expected[i].silentBar = true }                       // bar 1 silent
        let played = expected.map { PlayedNote(time: $0.time + ($0.bar == 2 ? 0.03 : 0)) }   // late after the silence
        let graded = RhythmGrader.grade(expected: expected, played: played)
        #expect(abs((RhythmStats.silenceDrift(graded) ?? 0) - 0.03) < 1e-9)
    }

    @Test("End to end: synthetic picked notes → onset detector → grader")
    func endToEnd() {
        let sr = 48_000.0
        // 8th notes at 120 BPM: expected every 0.25 s from 0.5 s; the player rushes by 7 ms and drags one note.
        let expected = (0..<16).map { i in ExpectedNote(time: 0.5 + Double(i) * 0.25, bar: i / 8, beat: (i % 8) / 2, tick: i % 2, interval: 0.25) }
        let offsets = (0..<16).map { $0 == 9 ? 0.03 : -0.007 }
        let notes = zip(expected, offsets).map { Plucks.Note(time: $0.time + $1, frequency: 110, amplitude: 0.8) }
        let signal = Plucks.render(notes, seconds: 5)
        let detector = OnsetDetector(configuration: OnsetConfiguration(sampleRate: sr))
        var onsets: [DetectedOnset] = []
        var i = 0
        while i < signal.count { onsets += detector.process(Array(signal[i..<min(i + 256, signal.count)])); i += 256 }
        if let last = detector.flush() { onsets.append(last) }
        let graded = RhythmGrader.grade(expected: expected, played: onsets.map { PlayedNote(time: $0.sample / sr) })
        #expect(graded.filter { $0.grade == .exact }.count == 15)       // −7 ms is inside «точно» = min(10, 8 % of 250 ms)
        #expect(graded.first { $0.expected?.time == expected[9].time }?.grade == .inaccurate)
        let bars = RhythmStats.bars(graded)
        #expect(bars.allSatisfy { $0.missing == 0 && $0.extra == 0 })
        #expect(abs((bars[0].meanDeviation ?? 0) + 0.007) < 0.001)
    }
}
