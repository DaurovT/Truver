import Foundation
import Testing
@testable import TruverDSP

@Suite("Guitar pluck (SND-6)")
struct GuitarPluckTests {
    /// Frequency by interpolated rising zero crossings over a window.
    private func measuredFrequency(_ s: [Float], rate: Double, from: Int, count: Int) -> Double {
        var crossings: [Double] = []
        for i in from..<(from + count - 1) where s[i] <= 0 && s[i + 1] > 0 {
            crossings.append(Double(i) + Double(-s[i] / (s[i + 1] - s[i])))
        }
        guard crossings.count > 2 else { return 0 }
        return rate * Double(crossings.count - 1) / (crossings.last! - crossings.first!)
    }

    @Test("Pitch within ±1 cent from B1 to E5", arguments: [61.74, 82.41, 329.63, 659.26])
    func pitch(frequency: Double) {
        let rate = 48_000.0
        let synth = NoteSynth(sampleRate: rate)
        synth.schedule(frequency: frequency, at: 0, velocity: 0.8, kind: .pluck, string: 0)
        var out = [Float](repeating: 0, count: Int(rate * 1.2))
        out.withUnsafeMutableBufferPointer { p in
            var t: Int64 = 0
            while Int(t) < p.count {
                let n = min(512, p.count - Int(t))
                synth.render(adding: p.baseAddress! + Int(t), frameCount: n, sampleTime: t)
                t += Int64(n)
            }
        }
        // Lowpass a little so harmonics do not add crossings.
        var smooth = out
        let alpha = Float(1 - exp(-2 * Double.pi * frequency * 1.1 / rate))
        for _ in 0..<6 { for i in 1..<smooth.count { smooth[i] = smooth[i - 1] + alpha * (smooth[i] - smooth[i - 1]) } }
        let f = measuredFrequency(smooth, rate: rate, from: Int(rate * 0.3), count: Int(rate * 0.8))
        let cents = 1200 * log2(f / frequency)
        #expect(abs(cents) < 1, "\(frequency) Hz → \(f) Hz (\(cents) c)")
    }

    @Test("A new note on the same string damps the previous one")
    func sameStringDamps() {
        let synth = NoteSynth(sampleRate: 48_000)
        synth.schedule(frequency: 110, at: 0, kind: .pluck, string: 2)
        synth.schedule(frequency: 123.47, at: 4_800, kind: .pluck, string: 2)
        var out = [Float](repeating: 0, count: 48_000)
        out.withUnsafeMutableBufferPointer { synth.render(adding: $0.baseAddress!, frameCount: $0.count, sampleTime: 0) }
        #expect(synth.activeVoiceCount == 1)
    }

    @Test("Many ringing notes never exceed full scale")
    func noClipping() {
        let synth = NoteSynth(sampleRate: 48_000)
        for i in 0..<30 { synth.schedule(frequency: 82.41 * pow(2, Double(i % 24) / 12), at: Int64(i * 2_000), velocity: 1, kind: .pluck) }
        var out = [Float](repeating: 0, count: 96_000)
        out.withUnsafeMutableBufferPointer { synth.render(adding: $0.baseAddress!, frameCount: $0.count, sampleTime: 0) }
        #expect((out.map(abs).max() ?? 0) <= 1.0)
    }
}
