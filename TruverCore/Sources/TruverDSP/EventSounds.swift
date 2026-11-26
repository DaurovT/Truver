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

/// SND-3: event signals of the metronome — «цель достигнута» (a mode reached its target tempo) and «таймер
/// истёк» (the practice timer ran out). Tonal and long (≥ 0.25 s) so they never pass for a click (15–30 ms,
/// noise-like), and 6 dB below the strong click of the current set by peak.
public enum EventSound: String, CaseIterable, Sendable, Codable {
    case targetReached
    case timerEnded
}

public enum EventSounds {
    /// −6 dB relative to the click (SND-3).
    public static let levelBelowClick: Float = 0.5

    /// Synthesized signal, peak = `levelBelowClick` × the peak of `clicks.strong`.
    public static func make(_ sound: EventSound, sampleRate: Double, clicks: ClickSounds) -> [Float] {
        let clickPeak = clicks.strong.reduce(Float(0)) { max($0, abs($1)) }
        let raw: [Float]
        switch sound {
        case .targetReached:
            // Rising major sixth E6 → C♯7: «up, done».
            raw = chime([(1318.5, 0), (2217.5, 0.11)], length: 0.42, sampleRate: sampleRate)
        case .timerEnded:
            // Two equal lower tones A5, A5: «time».
            raw = chime([(880, 0), (880, 0.22)], length: 0.5, sampleRate: sampleRate)
        }
        let peak = raw.reduce(Float(0)) { max($0, abs($1)) }
        guard peak > 0 else { return raw }
        let scale = levelBelowClick * max(clickPeak, 0.05) / peak
        return raw.map { $0 * scale }
    }

    /// Soft bell strokes: fundamental + octave + a faint twelfth, 4 ms attack, exponential decay.
    static func chime(_ strokes: [(frequency: Double, at: Double)], length: Double, sampleRate: Double) -> [Float] {
        let count = Int(length * sampleRate)
        var out = [Float](repeating: 0, count: count)
        let attack = 0.004 * sampleRate
        for stroke in strokes {
            let first = Int(stroke.at * sampleRate)
            guard first < count else { continue }
            for i in first..<count {
                let n = Double(i - first)
                let t = n / sampleRate
                let envelope = min(1, n / attack) * exp(-t / 0.09)
                let w = 2 * Double.pi * stroke.frequency * t
                let s = sin(w) + 0.3 * sin(2 * w) * exp(-t / 0.04) + 0.12 * sin(3 * w) * exp(-t / 0.025)
                out[i] += Float(envelope * s)
            }
        }
        // 10 ms fade-out: no click at the end of the buffer.
        let fade = min(count, Int(0.01 * sampleRate))
        for k in 0..<fade { out[count - 1 - k] *= Float(k) / Float(fade) }
        return out
    }
}
