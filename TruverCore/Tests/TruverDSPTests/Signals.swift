import Foundation

/// Synthetic test signals (PRD 11: "синтетические сигналы с обертонами").
enum Signals {
    static let sampleRate = 48_000.0

    /// A harmonic tone. `harmonics[k]` is the amplitude of harmonic k+1. Optional exponential decay (string-like).
    static func tone(_ frequency: Double, seconds: Double, harmonics: [Double] = [1, 0.5, 0.33, 0.25, 0.2],
                     amplitude: Double = 0.3, decaySeconds: Double? = nil, sampleRate: Double = sampleRate) -> [Float] {
        let count = Int(seconds * sampleRate)
        let attack = Int(0.003 * sampleRate)
        return (0..<count).map { i in
            let t = Double(i) / sampleRate
            var v = 0.0
            for (k, a) in harmonics.enumerated() where a != 0 {
                v += a * sin(2 * .pi * frequency * Double(k + 1) * t + Double(k) * 0.7)
            }
            var envelope = i < attack ? Double(i) / Double(attack) : 1
            if let decaySeconds { envelope *= exp(-t / decaySeconds) }
            return Float(amplitude * envelope * v)
        }
    }

    static func silence(seconds: Double, sampleRate: Double = sampleRate) -> [Float] {
        Array(repeating: 0, count: Int(seconds * sampleRate))
    }

    /// Low-level deterministic noise (linear congruential), for a realistic noise floor.
    static func noise(count: Int, level: Float = 0.0005, seed: UInt64 = 1) -> [Float] {
        var state = seed
        return (0..<count).map { _ in
            state = state &* 6364136223846793005 &+ 1442695040888963407
            return (Float(state >> 40) / Float(1 << 24) - 0.5) * 2 * level
        }
    }

    static func add(_ a: [Float], _ b: [Float]) -> [Float] {
        zip(a, b).map { $0 + $1 } + (a.count > b.count ? Array(a[b.count...]) : Array(b[a.count...]))
    }

    static func hz(_ note: String) -> Double {
        let names = ["C": 0, "D": 2, "E": 4, "F": 5, "G": 7, "A": 9, "B": 11]
        var chars = Array(note)
        var pc = names[String(chars.removeFirst())]!
        while let c = chars.first, c == "#" || c == "♯" || c == "b" || c == "♭" {
            pc += (c == "#" || c == "♯") ? 1 : -1
            chars.removeFirst()
        }
        let octave = Int(String(chars))!
        let midi = 12 * (octave + 1) + pc
        return 440 * pow(2, Double(midi - 69) / 12)
    }

    static func cents(_ measured: Double, _ expected: Double) -> Double { 1200 * log2(measured / expected) }
}
