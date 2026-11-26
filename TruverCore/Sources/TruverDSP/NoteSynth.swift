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

/// Note sounds of the app (TU-9 reference tone, FB-7 tap on a fret, FB-8 scale playback, FB-13 drone).
///
/// Plucked notes (SND-6): a Karplus–Strong string with a first-order all-pass fractional delay — the pitch stays
/// exact (an integer delay would be off by up to ~18 cents at the top of the neck), excited with the triangular shape
/// of a plucked string plus a little pick noise; lower strings are scaled down so they do not boom. A new note on the same string damps the previous one, like a real guitar.
/// The reference tone (SND-2) stays additive: steady, 4–6 harmonics. The mix goes through a soft limiter, so many
/// ringing notes never clip. Fixed voice pools; buffers are allocated when scheduling, never while rendering.
public final class NoteSynth {
    public enum Kind: Sendable {
        /// Plucked string: fast attack, harmonics decay faster than the fundamental.
        case pluck
        /// Reference tone: steady for `duration`, then a short release (TU-9).
        case reference(duration: Double)
    }

    public let sampleRate: Double
    public var volume: Float = 0.6
    /// Reference tone and drone (SND-7: their own slider).
    public var referenceVolume: Float = 0.6

    private static let harmonicCount = 6
    private struct Voice {
        var start: Int64
        var phase: [Double]
        var increment: [Double]
        var amplitude: [Double]
        var decayPerSample: [Double]
        var gain: Double
        var sustainSamples: Int64
        var releaseSamples: Int64
        var age: Int64 = 0
    }

    private var voices: [Voice?]
    var plucks: [Pluck?]

    /// FB-13 / SND-5 drone: one steady organ-like tone on the tonic — no vibrato, no tremolo, so the tuner and
    /// the ear are not disturbed; fades in over 0.3 s and out over 0.5 s. Fixed arrays, no allocation in render.
    private static let droneHarmonics: [Double] = [1.0, 0.5, 0.33, 0.25, 0.12, 0.08]
    private var dronePhase = [Double](repeating: 0, count: 6)
    private var droneIncrement = [Double](repeating: 0, count: 6)
    private var droneLevel = 0.0
    private var droneTarget = 0.0
    /// True while the drone sounds or fades out.
    public var isDroning: Bool { droneLevel > 0.0001 || droneTarget > 0 }

    /// Starts (or retunes) the drone. Retuning keeps the phase, so there is no click.
    public func startDrone(frequency: Double) {
        for k in 0..<droneIncrement.count {
            let f = frequency * Double(k + 1)
            droneIncrement[k] = f < sampleRate * 0.45 ? 2 * Double.pi * f / sampleRate : 0
        }
        droneTarget = 1
    }

    public func stopDrone() { droneTarget = 0 }

    private func renderDrone(adding output: UnsafeMutablePointer<Float>, frameCount: Int, peak: inout Float) {
        guard isDroning else { return }
        let up = 1 / (0.3 * sampleRate), down = 1 / (0.5 * sampleRate)
        for frame in 0..<frameCount {
            if droneLevel < droneTarget { droneLevel = min(droneTarget, droneLevel + up) }
            else if droneLevel > droneTarget { droneLevel = max(droneTarget, droneLevel - down) }
            var sample = 0.0
            for k in 0..<droneIncrement.count where droneIncrement[k] > 0 {
                sample += NoteSynth.droneHarmonics[k] * sin(dronePhase[k])
                dronePhase[k] += droneIncrement[k]
                if dronePhase[k] > 2 * Double.pi { dronePhase[k] -= 2 * Double.pi }
            }
            let value = Float(sample * droneLevel * 0.16) * referenceVolume
            output[frame] += value
            peak = max(peak, abs(value))
        }
    }

    public init(sampleRate: Double, maxVoices: Int = 24) {
        self.sampleRate = sampleRate
        self.voices = Array(repeating: nil, count: maxVoices)
        self.plucks = Array(repeating: nil, count: 128)
    }

    /// Schedules a note at `sampleTime` on the output timeline. If the pool is full, the oldest voice is replaced.
    /// `duration`: the note is damped after this many seconds (FB-8: one subdivision, no overlap; FB-23: 2 s).
    public func schedule(frequency: Double, at sampleTime: Int64, velocity: Double = 0.8, kind: Kind = .pluck, string: Int? = nil,
                         duration: Double? = nil) {
        if case .pluck = kind {
            schedulePluck(frequency: frequency, at: sampleTime, velocity: velocity, string: string, duration: duration)
            return
        }
        let n = NoteSynth.harmonicCount
        var amplitude = [Double](repeating: 0, count: n)
        var decay = [Double](repeating: 1, count: n)
        var increment = [Double](repeating: 0, count: n)
        var sustain: Int64 = 0
        var release: Int64 = Int64(0.05 * sampleRate)
        for k in 0..<n {
            let f = frequency * Double(k + 1)
            guard f < sampleRate * 0.45 else { continue }
            increment[k] = 2 * Double.pi * f / sampleRate
            switch kind {
            case .pluck:
                amplitude[k] = [1.0, 0.55, 0.35, 0.22, 0.14, 0.09][k]
                // Higher harmonics fade faster; low notes ring longer.
                let seconds = max(0.4, min(3.0, 1.6 * pow(110 / frequency, 0.3))) / Double(1 + k)
                decay[k] = exp(-1 / (seconds * sampleRate))
            case .reference(let duration):
                amplitude[k] = [1.0, 0.4, 0.2, 0.1, 0.05, 0.03][k]
                sustain = Int64(duration * sampleRate)
                release = Int64(0.15 * sampleRate)
            }
        }
        let voice = Voice(start: sampleTime, phase: Array(repeating: 0, count: n), increment: increment,
                          amplitude: amplitude, decayPerSample: decay, gain: velocity,
                          sustainSamples: sustain, releaseSamples: release)
        if let free = voices.firstIndex(where: { $0 == nil }) {
            voices[free] = voice
        } else if let oldest = voices.indices.max(by: { (voices[$0]?.age ?? 0) < (voices[$1]?.age ?? 0) }) {
            voices[oldest] = voice
        }
    }

    /// Notes stop at once; the drone (its own control) keeps sounding.
    public func stopAll() {
        for i in voices.indices { voices[i] = nil }
        for i in plucks.indices { plucks[i] = nil }
    }

    public var isPlaying: Bool { voices.contains { $0 != nil } || plucks.contains { $0.map { !$0.done } ?? false } }
    /// Peak of the synth's own contribution in the last rendered block (debug / meters).
    public private(set) var lastBlockPeak: Float = 0
    public var activeVoiceCount: Int { voices.reduce(0) { $0 + ($1 == nil ? 0 : 1) } + plucks.reduce(0) { $0 + (($1.map { !$0.done } ?? false) ? 1 : 0) } }

    /// Adds the voices into `output` (mono) for the block starting at `sampleTime`.
    public func render(adding output: UnsafeMutablePointer<Float>, frameCount: Int, sampleTime: Int64) {
        var peak: Float = 0
        defer { lastBlockPeak = peak }
        renderPlucks(adding: output, frameCount: frameCount, sampleTime: sampleTime, peak: &peak)
        renderDrone(adding: output, frameCount: frameCount, peak: &peak)
        for slot in voices.indices {
            guard var v = voices[slot] else { continue }
            let first = max(0, Int(v.start - sampleTime))
            guard first < frameCount else { continue }
            var finished = false
            for frame in first..<frameCount {
                var envelope = v.gain
                let attack = 0.002 * sampleRate
                if Double(v.age) < attack { envelope *= Double(v.age) / attack }
                if v.sustainSamples > 0 && v.age > v.sustainSamples {
                    let r = Double(v.age - v.sustainSamples) / Double(max(1, v.releaseSamples))
                    if r >= 1 { finished = true; break }
                    envelope *= 1 - r
                }
                var sample = 0.0
                var loudest = 0.0
                for k in 0..<NoteSynth.harmonicCount where v.amplitude[k] > 0 {
                    sample += v.amplitude[k] * sin(v.phase[k])
                    v.phase[k] += v.increment[k]
                    if v.phase[k] > 2 * Double.pi { v.phase[k] -= 2 * Double.pi }
                    v.amplitude[k] *= v.decayPerSample[k]
                    loudest = max(loudest, v.amplitude[k])
                }
                let value = Float(sample * envelope * 0.35) * referenceVolume
                output[frame] += value
                peak = max(peak, abs(value))
                v.age += 1
                if loudest < 0.0005 { finished = true; break }
            }
            voices[slot] = finished ? nil : v
        }
    }
}

extension MetronomeClock {
    /// Sample time of the next bar start, assuming the current tempo holds (FB-8: the scale starts on the next
    /// strong beat of a running metronome, 6.1 п. 14). Nil when stopped.
    public func nextBarStart() -> Int64? {
        guard isRunning else { return nil }
        let beatLength = 60 / settings.bpm * sampleRate
        let beatsLeft = upcomingBeatIndex == 0 ? 0 : settings.numerator - upcomingBeatIndex
        return Int64((upcomingBeatTime + Double(beatsLeft) * beatLength).rounded())
    }
}

// MARK: Plucked string (SND-6)

extension NoteSynth {
    final class Pluck {
        var start: Int64
        var age: Int64 = 0
        let string: Int?
        /// Damping starts here (a newer note on the same string, or stopAll); then a 40 ms fade.
        var cutAt: Int64 = .max
        var delay: [Float]
        var index = 0
        var lastOut: Float = 0
        var apIn: Float = 0
        var apOut: Float = 0
        let apCoefficient: Float
        let loss: Float
        let gain: Float
        var silentRun = 0
        /// Finished on the render thread; the slot is reused (and the buffer freed) on the next schedule.
        var done = false

        init(frequency: Double, sampleRate: Double, start: Int64, velocity: Double, string: Int?) {
            self.start = start
            self.string = string
            // Loop delay: L samples + 0.5 (averaging filter) + all-pass fraction in 0.1…1.1.
            let total = sampleRate / frequency - 0.5
            let length = max(2, Int(floor(total - 0.1)))
            let fraction = total - Double(length)
            apCoefficient = Float((1 - fraction) / (1 + fraction))
            // Decay: low notes ring ~4 s, high ~1.2 s (T60 per loop pass).
            let t60 = max(1.5, min(4.0, 3.2 * pow(110 / frequency, 0.35)))   // SND-6: −60 dB in 1.5–4 s
            loss = Float(pow(10, -3 / (frequency * t60)))
            // Loudness: long delay lines (low strings) hold more energy — scale them down so basses don't boom.
            // SND-6: about −12 dBFS per stroke (peak ≈ 0.25 at velocity 0.8).
            gain = Float(0.27 * velocity * min(1.0, max(0.45, pow(frequency / 220, 0.35))))
            // Excitation: the shape of a plucked string — a triangle peaking at the pick point (~1/6 of the string
            // from the bridge) — plus a little lowpassed noise for the pick's grit. White noise alone sounds like hiss.
            var seed: UInt32 = 0x1234_5678 &+ UInt32(truncatingIfNeeded: Int(frequency * 100))
            let pickPoint = max(1, length / 6)
            var buffer = [Float](repeating: 0, count: length)
            var lp: Float = 0
            let grit: Float = Float(0.12 + 0.1 * velocity)
            for i in 0..<length {
                let shape: Float = i <= pickPoint ? Float(i) / Float(pickPoint) : Float(length - i) / Float(length - pickPoint)
                seed = seed &* 1_664_525 &+ 1_013_904_223
                let noise = Float(Int32(bitPattern: seed)) / Float(Int32.max)
                lp += 0.3 * (noise - lp)
                buffer[i] = shape + grit * lp
            }
            // Soften the corners (a pick is not a knife): two passes of a 3-tap average around the loop.
            // Low strings sound darker (SND-6: timbre by string thickness): more smoothing below 100 / 200 Hz.
            let passes = frequency < 100 ? 4 : (frequency < 200 ? 3 : 2)
            for _ in 0..<passes {
                let copy = buffer
                for i in 0..<length { buffer[i] = 0.25 * copy[(i + length - 1) % length] + 0.5 * copy[i] + 0.25 * copy[(i + 1) % length] }
            }
            let mean = buffer.reduce(0, +) / Float(length)
            let peak = buffer.map { abs($0 - mean) }.max() ?? 1
            delay = buffer.map { ($0 - mean) / max(peak, 0.0001) }
        }

        /// One output sample.
        @inline(__always) func next() -> Float {
            let x = delay[index]
            let averaged = 0.5 * (x + lastOut) * loss
            lastOut = x
            let y = apCoefficient * averaged + apIn - apCoefficient * apOut
            apIn = averaged
            apOut = y
            delay[index] = y
            index += 1
            if index == delay.count { index = 0 }
            return y * gain
        }
    }

    func schedulePluck(frequency: Double, at sampleTime: Int64, velocity: Double, string: Int?, duration: Double? = nil) {
        guard frequency > 20, frequency < sampleRate * 0.4 else { return }
        if let string {
            for case let p? in plucks where p.string == string && p.start < sampleTime { p.cutAt = min(p.cutAt, sampleTime) }
        }
        let pluck = Pluck(frequency: frequency, sampleRate: sampleRate, start: sampleTime, velocity: velocity, string: string)
        if let duration { pluck.cutAt = sampleTime + Int64(duration * sampleRate) }
        if let free = plucks.firstIndex(where: { $0 == nil || $0?.done == true }) {
            plucks[free] = pluck
        } else if let oldest = plucks.indices.min(by: { (plucks[$0]?.start ?? .max) < (plucks[$1]?.start ?? .max) }) {
            plucks[oldest] = pluck
        }
    }

    func renderPlucks(adding output: UnsafeMutablePointer<Float>, frameCount: Int, sampleTime: Int64, peak: inout Float) {
        let fade = Int64(0.04 * sampleRate)
        for slot in plucks.indices {
            guard let p = plucks[slot], !p.done else { continue }
            let first = max(0, Int(p.start - sampleTime))
            guard first < frameCount else { continue }
            var finished = false
            for frame in first..<frameCount {
                let now = sampleTime + Int64(frame)
                var value = p.next()
                if now >= p.cutAt {
                    let r = Double(now - p.cutAt) / Double(fade)
                    if r >= 1 { finished = true; break }
                    value *= Float(1 - r)
                }
                if p.age < 64 { value *= Float(p.age) / 64 }   // click-free start
                let mixed = value * volume
                output[frame] += mixed
                peak = max(peak, abs(mixed))
                p.age += 1
                if abs(value) < 0.00005 { p.silentRun += 1 } else { p.silentRun = 0 }
                if p.silentRun > 2400 { finished = true; break }
            }
            if finished { p.done = true }
        }
        // Limit the whole block softly (clicks and notes share the buffer).
        for frame in 0..<frameCount {
            let x = output[frame]
            let magnitude: Float = abs(x)
            if magnitude > 0.7 {
                let excess: Float = (magnitude - 0.7) / 0.3
                let limited: Float = 0.7 + 0.3 * tanhf(excess)
                output[frame] = x > 0 ? limited : -limited
            }
        }
    }
}
