import Foundation
import Testing
@testable import TruverDSP

/// Synthetic picked notes with exactly known attack times.
enum Plucks {
    struct Note { var time: Double; var frequency: Double; var amplitude: Double }

    static func lcg(_ state: inout UInt64) -> Double {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return Double(state >> 11) / Double(1 << 53)
    }

    /// Picked strings: a short broadband pick noise + harmonic tone with 1 ms attack; earlier notes keep ringing.
    static func render(_ notes: [Note], seconds: Double, sampleRate: Double = 48_000, pickNoise: Bool = true,
                       decay: Double = 1.0, noiseLevel: Float = 0.0005) -> [Float] {
        var out = Signals.noise(count: Int(seconds * sampleRate), level: noiseLevel, seed: 3)
        var state: UInt64 = 42
        let harmonics: [Double] = [1, 0.6, 0.4, 0.3, 0.2, 0.15]
        for note in notes {
            let start = Int(note.time * sampleRate)
            let length = min(out.count - start, Int(min(decay * 5, seconds) * sampleRate))
            guard length > 0 else { continue }
            for i in 0..<length {
                let t = Double(i) / sampleRate
                let attack = min(1, t / 0.001)
                var v = 0.0
                for (k, a) in harmonics.enumerated() {
                    v += a * sin(2 * .pi * note.frequency * Double(k + 1) * t)
                }
                var sample = 0.25 * note.amplitude * attack * exp(-t / decay) * v
                if pickNoise && t < 0.0015 {
                    sample += 0.4 * note.amplitude * (lcg(&state) - 0.5) * (1 - t / 0.0015)
                }
                out[start + i] += Float(sample)
            }
        }
        return out
    }

    /// 16ths at `bpm` with ±jitter, amplitudes 0.35…1.0, pitches walking a scale.
    static func passage(count: Int, bpm: Double, jitter: Double, seed: UInt64 = 7, lead: Double = 0.3) -> [Note] {
        var state = seed
        let scale = [82.41, 92.5, 98.0, 110.0, 123.47, 130.81, 146.83, 164.81, 185.0, 196.0]
        return (0..<count).map { i in
            let ideal = lead + Double(i) * 60 / bpm / 4
            let offset = (lcg(&state) * 2 - 1) * jitter
            let amplitude = 0.35 + 0.65 * lcg(&state)
            return Note(time: ideal + offset, frequency: scale[i % scale.count], amplitude: amplitude)
        }
    }
}

@Suite("Onset detector (SM-1)")
struct OnsetTests {
    let sr = 48_000.0

    struct Result { var errorsMs: [Double]; var missed: Int; var extra: Int }

    func evaluate(_ notes: [Plucks.Note], _ signal: [Float], block: Int = 256) -> Result {
        let detector = OnsetDetector(configuration: OnsetConfiguration(sampleRate: sr))
        var onsets: [DetectedOnset] = []
        var i = 0
        while i < signal.count {
            onsets += detector.process(Array(signal[i..<min(i + block, signal.count)]))
            i += block
        }
        if let last = detector.flush() { onsets.append(last) }
        var used = Set<Int>()
        var errors: [Double] = []
        for note in notes {
            let candidates = onsets.indices.filter { !used.contains($0) && abs(onsets[$0].sample / sr - note.time) < 0.02 }
            guard let best = candidates.min(by: { abs(onsets[$0].sample / sr - note.time) < abs(onsets[$1].sample / sr - note.time) }) else { continue }
            used.insert(best)
            errors.append((onsets[best].sample / sr - note.time) * 1000)
        }
        return Result(errorsMs: errors, missed: notes.count - errors.count, extra: onsets.count - used.count)
    }

    func report(_ name: String, _ r: Result) {
        let sorted = r.errorsMs.map(abs).sorted()
        let median = sorted.isEmpty ? .nan : sorted[sorted.count / 2]
        let mean = r.errorsMs.isEmpty ? .nan : r.errorsMs.reduce(0, +) / Double(r.errorsMs.count)
        print(String(format: "ONSET %@: n=%d missed=%d extra=%d |err| median %.2f ms, max %.2f ms, bias %+.2f ms",
                     name, r.errorsMs.count, r.missed, r.extra, median, sorted.last ?? .nan, mean))
    }

    @Test("16ths at 120 BPM with pick noise: all found, |error| ≤ 2 ms")
    func picked16ths() {
        let notes = Plucks.passage(count: 32, bpm: 120, jitter: 0.008)
        let r = evaluate(notes, Plucks.render(notes, seconds: 5))
        report("picked 16ths 120", r)
        #expect(r.missed == 0)
        #expect(r.extra == 0)
        #expect(r.errorsMs.allSatisfy { abs($0) <= 2 })
    }

    @Test("16ths at 180 BPM (83 ms apart)")
    func fast16ths() {
        let notes = Plucks.passage(count: 40, bpm: 180, jitter: 0.006, seed: 11)
        let r = evaluate(notes, Plucks.render(notes, seconds: 4.5))
        report("picked 16ths 180", r)
        #expect(r.missed == 0)
        #expect(r.extra == 0)
        #expect(r.errorsMs.allSatisfy { abs($0) <= 3 })
    }

    /// Attacks with no transient at all (a pure tone fading in over 1 ms on top of ringing notes) look like the
    /// beating of the ringing notes; they may be missed — that is SM-10 "не распознано" — but must not create
    /// false onsets, and what is found must be accurate.
    @Test("Without pick noise: may be missed (SM-10), no false onsets")
    func softAttacks() {
        let notes = Plucks.passage(count: 24, bpm: 100, jitter: 0.01, seed: 5)
        let r = evaluate(notes, Plucks.render(notes, seconds: 5, pickNoise: false, decay: 1.5))
        report("soft attacks 100", r)
        #expect(r.extra == 0)
        #expect(r.errorsMs.allSatisfy { abs($0) <= 5 })
    }

    @Test("Metronome clicks are found on their sample")
    func clicks() {
        var signal = Signals.noise(count: Int(4 * sr), level: 0.0005)
        let click = ClickSounds.synthesized(sampleRate: sr).strong
        let times = (0..<6).map { 0.3 + Double($0) * 0.6 }
        for t in times {
            let start = Int(t * sr)
            for (i, v) in click.enumerated() { signal[start + i] += v * 0.3 }
        }
        let r = evaluate(times.map { Plucks.Note(time: $0, frequency: 0, amplitude: 1) }, signal)
        report("clicks", r)
        #expect(r.missed == 0 && r.extra == 0)
        #expect(r.errorsMs.allSatisfy { abs($0) <= 1 })
    }

    @Test("A sustained note does not produce onsets; silence neither")
    func noFalseOnsets() {
        let notes = [Plucks.Note(time: 0.2, frequency: 110, amplitude: 1)]
        let r = evaluate(notes, Plucks.render(notes, seconds: 3, decay: 3))
        #expect(r.missed == 0)
        #expect(r.extra == 0)
    }
}
