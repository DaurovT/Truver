import Foundation
import Testing
@testable import TruverDSP

@Suite("Rhythmic figures of the metronome (16-16-8, triplets, half notes)")
struct BeatRhythmTests {
    private let sr = 48_000.0

    private func audible(_ rhythm: BeatRhythm, numerator: Int = 4, seconds: Double = 2) -> [ClickEvent] {
        var settings = MeterSettings(bpm: 120, numerator: numerator)
        settings.rhythm = rhythm
        settings.subdivision = 1
        let clock = MetronomeClock(sampleRate: sr, settings: settings)
        clock.start(atSample: 0)
        return clock.events(from: 0, frameCount: Int(seconds * sr)).filter { !$0.isSilent }
    }

    @Test("16-16-8: clicks at 0, 1/4 and 1/2 of every beat")
    func sixteenSixteenEight() {
        let r = BeatRhythms.rhythm(id: "16:012")!
        #expect(r.durations == [1, 1, 2])
        let beat = Int64(24_000)
        let times = audible(r, seconds: 0.5).map(\.sampleTime)
        #expect(times == [0, beat / 4, beat / 2])
    }

    @Test("8-16-16 and 16-8-16 put the clicks where the notes are")
    func otherFigures() {
        #expect(audible(BeatRhythms.rhythm(id: "16:023")!, seconds: 0.5).map(\.sampleTime) == [0, 12_000, 18_000])
        #expect(audible(BeatRhythms.rhythm(id: "16:013")!, seconds: 0.5).map(\.sampleTime) == [0, 6_000, 18_000])
        #expect(audible(BeatRhythms.rhythm(id: "16:03")!, seconds: 0.5).map(\.sampleTime) == [0, 18_000])
    }

    @Test("Triplets and sextuplets: 3 and 6 even clicks per beat; shuffle skips the middle one")
    func tuplets() {
        #expect(audible(BeatRhythms.rhythm(id: "triplets")!, seconds: 0.5).count == 3)
        #expect(audible(BeatRhythms.rhythm(id: "sextuplets")!, seconds: 0.5).count == 6)
        #expect(audible(BeatRhythms.rhythm(id: "3:02")!, seconds: 0.5).map(\.sampleTime) == [0, 16_000])
        #expect(BeatRhythms.rhythm(id: "sextuplets")!.tuplet == 6)
        #expect(BeatRhythms.rhythm(id: "sixteenths")!.tuplet == nil)
    }

    @Test("Half notes click every other beat, whole notes once per bar; the first click keeps the accent")
    func longValues() {
        let half = audible(BeatRhythms.rhythm(id: "half")!, seconds: 4)
        #expect(half.map(\.beat) == [0, 2, 0, 2])
        let whole = audible(BeatRhythms.rhythm(id: "whole")!, seconds: 4)
        #expect(whole.map(\.beat) == [0, 0])
        #expect(whole.first?.level == .strong)
    }

    @Test("Off-beat figures leave the beat silent; old settings without a figure decode as before")
    func offbeatAndDecoding() throws {
        #expect(audible(BeatRhythms.rhythm(id: "eighth")!, seconds: 0.5).map(\.sampleTime) == [12_000])
        let old = #"{"bpm":100,"numerator":3,"denominator":4,"accents":[3,2,2],"subdivision":2,"swing":0.5}"#
        let decoded = try JSONDecoder().decode(MeterSettings.self, from: Data(old.utf8))
        #expect(decoded.rhythm == nil && decoded.subdivision == 2)
    }

    @Test("The library is large, has no duplicate figures, and every group is filled")
    func library() {
        let all = BeatRhythms.all
        #expect(all.count >= 120)
        #expect(Set(all.map(\.id)).count == all.count)
        let keys = all.map { "\($0.span):" + $0.positions().map { String(format: "%.4f", $0) }.joined(separator: ",") }
        #expect(Set(keys).count == keys.count)
        for g in BeatRhythmGroup.allCases { #expect(!BeatRhythms.figures(in: g).isEmpty, "\(g)") }
        #expect(BeatRhythms.rhythm(id: "16:012")!.shortName == "16-16-8")
        #expect(BeatRhythms.rhythm(id: "16:023")!.shortName == "8-16-16")
        #expect(BeatRhythms.rhythm(id: "16:03")!.shortName == "8.-16")
        #expect(BeatRhythms.rhythm(id: "quarter-triplets")!.tuplet == 3)
    }

    @Test("Figures over several beats: quarter triplets over two beats, son clave 3-2 over the bar")
    func multiBeat() {
        let qt = audible(BeatRhythms.rhythm(id: "quarter-triplets")!, seconds: 1)
        #expect(qt.map(\.sampleTime) == [0, 16_000, 32_000])
        let clave = audible(BeatRhythms.rhythm(id: "son-3-2")!, seconds: 2)
        let sixteenth = Int64(6_000)
        #expect(clave.map(\.sampleTime) == [0, 3, 6, 10, 12].map { $0 * sixteenth })
    }

    @Test("Per-beat figures: beat 1 eighths, beat 3 triplet, the rest quarters")
    func perBeat() {
        var settings = MeterSettings(bpm: 120, numerator: 4)
        settings.beatRhythms = [BeatRhythms.rhythm(id: "eighths"), nil, BeatRhythms.rhythm(id: "triplets"), nil]
        let clock = MetronomeClock(sampleRate: sr, settings: settings)
        clock.start(atSample: 0)
        let events = clock.events(from: 0, frameCount: 96_000).filter { !$0.isSilent }
        #expect(events.map(\.beat) == [0, 0, 1, 2, 2, 2, 3])
        #expect(events.map(\.sampleTime) == [0, 12_000, 24_000, 48_000, 56_000, 64_000, 72_000])
    }

    @Test("A rest on the beat is a rest, not a silent bar; a 4-beat figure runs on across 3/4 bar lines")
    func restAndBarLine() {
        var settings = MeterSettings(bpm: 120, numerator: 4)
        settings.rhythm = BeatRhythms.rhythm(id: "eighth")       // off-beat eighth: the beat is a rest
        let clock = MetronomeClock(sampleRate: sr, settings: settings)
        clock.start(atSample: 0)
        let beats = clock.events(from: 0, frameCount: 48_000).filter { $0.tick == 0 }
        #expect(beats.allSatisfy { $0.isSilent && $0.isRest })

        var waltz = MeterSettings(bpm: 120, numerator: 3)
        waltz.rhythm = BeatRhythms.rhythm(id: "son-3-2")          // 4 beats long
        let c2 = MetronomeClock(sampleRate: sr, settings: waltz)
        c2.start(atSample: 0)
        let clicks = c2.events(from: 0, frameCount: 192_000).filter { !$0.isSilent }.map(\.sampleTime)
        let sixteenth = Int64(6_000)
        // Son 3-2 over 4 beats = 16 sixteenths: 0 3 6 10 12, then again from 16 — across the 3/4 bar lines.
        #expect(clicks == [0, 3, 6, 10, 12, 16, 19, 22, 26, 28].map { $0 * sixteenth })
    }

    @Test("Names: no step counts, ties for odd lengths, polyrhythm ratios, words for VoiceOver")
    func names() {
        for r in BeatRhythms.all {
            #expect(!r.shortName.contains("5") && !r.shortName.contains("7") || r.shortName.contains("+") || r.group == .polyrhythm || r.group == .latin || r.group == .tuplets || r.group == .sextuplets, "\(r.id): \(r.shortName)")
            #expect(!BeatRhythms.spokenName(r).isEmpty)
        }
        #expect(BeatRhythms.rhythm(id: "poly5:3")!.tupletLabel == "5:3")
        #expect(BeatRhythms.rhythm(id: "quintuplets")!.tupletLabel == "5")
        #expect(BeatRhythms.spokenName(BeatRhythms.rhythm(id: "16:012")!) == "шестнадцатая, шестнадцатая, восьмая")
    }
}
