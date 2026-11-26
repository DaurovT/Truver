#if canImport(AVFoundation)
import AVFoundation
import Foundation
import Testing
@testable import TruverAudio

@Suite("Play check analyzer (SM-1 on the host clock)")
struct PlayCheckAnalyzerTests {
    /// Picked notes: 1.5 ms broadband pick noise + a decaying harmonic tone.
    func plucks(_ times: [Double], seconds: Double, sr: Double) -> [Float] {
        var state: UInt64 = 42
        // Noise floor as in the detector tests (a perfectly silent input is not realistic).
        var out = (0..<Int(seconds * sr)).map { _ -> Float in
            state = state &* 6364136223846793005 &+ 1442695040888963407
            return Float(Double(state >> 11) / Double(1 << 53) - 0.5) * 0.001
        }
        func noise() -> Double {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            return Double(state >> 11) / Double(1 << 53) - 0.5
        }
        for (n, time) in times.enumerated() {
            let f = [110.0, 146.8, 196.0, 123.5][n % 4]
            let start = Int(time * sr)
            for i in 0..<min(out.count - start, Int(0.6 * sr)) {
                let t = Double(i) / sr
                var v = 0.0
                for (k, a) in [1, 0.6, 0.4, 0.3, 0.2, 0.15].enumerated() { v += a * sin(2 * .pi * f * Double(k + 1) * t) }
                var s = 0.25 * min(1, t / 0.001) * exp(-t / 1.0) * v
                if t < 0.0015 { s += 0.4 * noise() * (1 - t / 0.0015) }
                out[start + i] += Float(s)
            }
        }
        return out
    }

    @Test("Attacks land on the host clock within 2 ms, input latency removed; level history says «звук есть»")
    func timing() {
        let sr = 48_000.0
        let latency = 0.005
        let base = 1_000.0                       // host clock seconds of the first sample (+ latency)
        let times = [0.30, 0.55, 0.80, 1.05, 1.30, 1.55]
        let signal = plucks(times, seconds: 2, sr: sr)
        let analyzer = PlayCheckAnalyzer(sampleRate: sr, inputLatency: latency)
        var i = 0
        while i < signal.count {
            let block = Array(signal[i..<min(signal.count, i + 1024)])
            let host = AVAudioTime.hostTime(forSeconds: base + latency + Double(i) / sr)
            analyzer.process(block, hostTime: host)
            i += 1024
        }
        analyzer.waitUntilProcessed()
        let found = analyzer.onsets(from: base, to: base + 2).map { $0.time - base }
        // Every attack is found on time. (The detector may add a late false attack on overlapping ringing notes —
        // a detector matter, to be checked on live playing; the analyser's job is the clock.)
        for t in times {
            let nearest = found.min { abs($0 - t) < abs($1 - t) } ?? -1
            #expect(abs(nearest - t) < 0.002, "nearest \(nearest) for \(t) in \(found)")
        }
        #expect(analyzer.isSounding(at: base + 0.4))
        #expect(!analyzer.isSounding(at: base + 0.1))
    }
}

#endif
