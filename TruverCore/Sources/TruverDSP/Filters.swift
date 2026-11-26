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

/// Second-order IIR filter (RBJ cookbook), transposed direct form II.
public struct Biquad: Sendable {
    var b0: Double, b1: Double, b2: Double, a1: Double, a2: Double
    var z1 = 0.0, z2 = 0.0

    public static func highPass(cutoff: Double, sampleRate: Double, q: Double = 0.7071) -> Biquad {
        let w = 2 * Double.pi * cutoff / sampleRate
        let alpha = sin(w) / (2 * q), cosw = cos(w)
        let a0 = 1 + alpha
        return Biquad(b0: (1 + cosw) / 2 / a0, b1: -(1 + cosw) / a0, b2: (1 + cosw) / 2 / a0,
                      a1: -2 * cosw / a0, a2: (1 - alpha) / a0)
    }

    public static func lowPass(cutoff: Double, sampleRate: Double, q: Double = 0.7071) -> Biquad {
        let w = 2 * Double.pi * min(cutoff, sampleRate * 0.45) / sampleRate
        let alpha = sin(w) / (2 * q), cosw = cos(w)
        let a0 = 1 + alpha
        return Biquad(b0: (1 - cosw) / 2 / a0, b1: (1 - cosw) / a0, b2: (1 - cosw) / 2 / a0,
                      a1: -2 * cosw / a0, a2: (1 - alpha) / a0)
    }

    public mutating func process(_ x: Double) -> Double {
        let y = b0 * x + z1
        z1 = b1 * x - a1 * y + z2
        z2 = b2 * x - a2 * y
        return y
    }

    public mutating func process(_ buffer: inout [Float]) {
        for i in buffer.indices { buffer[i] = Float(process(Double(buffer[i]))) }
    }

    public mutating func reset() {
        z1 = 0
        z2 = 0
    }
}

/// Input conditioning of the tuner (TU-3): high-pass below 25 Hz and a low-pass above the instrument's range.
public struct InputFilter: Sendable {
    var highPass: Biquad
    var lowPass: Biquad

    public init(sampleRate: Double, highestFrequency: Double) {
        highPass = .highPass(cutoff: 25, sampleRate: sampleRate)
        // Keep the 4th harmonic of the highest string: the low-pass only removes hiss and pick noise.
        lowPass = .lowPass(cutoff: max(1000, highestFrequency * 4), sampleRate: sampleRate)
    }

    public mutating func process(_ buffer: inout [Float]) {
        for i in buffer.indices {
            buffer[i] = Float(lowPass.process(highPass.process(Double(buffer[i]))))
        }
    }
}

public enum Level {
    public static func rmsDB(_ samples: ArraySlice<Float>) -> Double {
        guard !samples.isEmpty else { return -160 }
        var sum = 0.0
        for v in samples { sum += Double(v) * Double(v) }
        let rms = (sum / Double(samples.count)).squareRoot()
        return rms > 0 ? 20 * log10(rms) : -160
    }
}
