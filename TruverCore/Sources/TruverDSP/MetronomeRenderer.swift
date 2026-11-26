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

/// Click samples per accent level (ME-5). The default set sits above the guitar's fundamental range
/// (SM-7: easier to separate from playing in the microphone).
public struct ClickSounds: Sendable {
    public var strong: [Float]
    public var normal: [Float]
    public var soft: [Float]
    /// ME-8 second track: a lower, rounder bell so it does not merge with the main clicks.
    public var polyStrong: [Float] = []
    public var poly: [Float] = []

    public init(strong: [Float], normal: [Float], soft: [Float]) {
        self.strong = strong
        self.normal = normal
        self.soft = soft
    }

    /// Two-partial bell, 40 ms.
    static func bell(_ frequency: Double, gain: Double, sampleRate: Double) -> [Float] {
        let count = Int(0.04 * sampleRate)
        return (0..<count).map { i in
            let t = Double(i) / sampleRate
            let envelope = min(1, Double(i) / max(1, 0.0005 * sampleRate)) * exp(-t / 0.012)
            return Float(gain * 0.6 * envelope * (sin(2 * .pi * frequency * t) + 0.6 * sin(2 * .pi * frequency * 1.504 * t)))
        }
    }

    func samples(for level: AccentLevel, track: Int) -> [Float]? {
        guard track == 1 else { return samples(for: level) }
        if level == .off { return nil }
        return level == .strong ? polyStrong : poly
    }

    /// Click sets of the «Звуки и выходы» sheet (ME-5).
    /// Canvas «Звуки и выход»: Щелчок, Дерево, Бип (`electronic`), Хай-хэт, Голос.
    public enum Kind: String, Codable, CaseIterable, Sendable {
        case click, wood, electronic, hiHat, voice
    }

    /// Default «Громкость акцента» (canvas: +6 дБ).
    public static let defaultAccentDB: Double = 6

    public static func synthesized(sampleRate: Double) -> ClickSounds {
        make(.click, sampleRate: sampleRate)
    }

    /// `accentDB` — the strong beat over the normal one («Громкость акцента», −3…+17 dB); nil keeps the set's own
    /// balance.
    public static func make(_ kind: Kind, sampleRate: Double, accentDB: Double? = nil) -> ClickSounds {
        var sounds = makeMain(kind, sampleRate: sampleRate)
        if let db = accentDB {
            // The strong click is the normal one raised by `db` (its own timbre kept): scale it to that level.
            let normalPeak = sounds.normal.reduce(0) { max($0, abs($1)) }
            let strongPeak = sounds.strong.reduce(0) { max($0, abs($1)) }
            if normalPeak > 0, strongPeak > 0 {
                let gain = Float(Double(normalPeak) * pow(10, db / 20) / Double(strongPeak))
                sounds.strong = sounds.strong.map { $0 * gain }
            }
        }
        sounds.polyStrong = bell(880, gain: 0.85, sampleRate: sampleRate)
        sounds.poly = bell(780, gain: 0.6, sampleRate: sampleRate)
        return sounds
    }

    static func makeMain(_ kind: Kind, sampleRate: Double) -> ClickSounds {
        switch kind {
        case .click:
            return ClickSounds(strong: tone(3200, gain: 1.0, sampleRate: sampleRate),
                               normal: tone(2400, gain: 0.7, sampleRate: sampleRate),
                               soft: tone(2400, gain: 0.35, sampleRate: sampleRate))
        case .wood:
            return ClickSounds(strong: wood(1900, gain: 1.0, sampleRate: sampleRate),
                               normal: wood(1400, gain: 0.75, sampleRate: sampleRate),
                               soft: wood(1400, gain: 0.4, sampleRate: sampleRate))
        case .electronic:
            return ClickSounds(strong: beep(1760, gain: 0.8, sampleRate: sampleRate),
                               normal: beep(1320, gain: 0.6, sampleRate: sampleRate),
                               soft: beep(1320, gain: 0.3, sampleRate: sampleRate))
        case .hiHat:
            return ClickSounds(strong: hiHat(decay: 0.012, gain: 0.9, sampleRate: sampleRate),
                               normal: hiHat(decay: 0.007, gain: 0.6, sampleRate: sampleRate),
                               soft: hiHat(decay: 0.007, gain: 0.3, sampleRate: sampleRate))
        case .voice:
            return ClickSounds(strong: voice(pitch: 210, gain: 0.9, sampleRate: sampleRate),
                               normal: voice(pitch: 170, gain: 0.6, sampleRate: sampleRate),
                               soft: voice(pitch: 170, gain: 0.3, sampleRate: sampleRate))
        }
    }

    /// Closed hi-hat: high-passed noise (first difference of a fixed LCG sequence) with a fast decay, 45 ms.
    static func hiHat(decay: Double, gain: Double, sampleRate: Double) -> [Float] {
        let count = Int(0.045 * sampleRate)
        var seed: UInt32 = 0x2545F491
        var previous = 0.0
        return (0..<count).map { i in
            seed = seed &* 1_664_525 &+ 1_013_904_223
            let noise = Double(Int32(bitPattern: seed)) / Double(Int32.max)
            let high = noise - previous
            previous = noise
            let t = Double(i) / sampleRate
            let envelope = min(1, Double(i) / max(1, 0.0003 * sampleRate)) * exp(-t / decay)
            return Float(gain * 0.5 * envelope * high)
        }
    }

    /// «Голос»: a short sung «та» — harmonics of `pitch` shaped by the formants of «а» (700, 1220, 2600 Hz), 90 ms.
    /// A synthetic stand-in until recorded counting samples exist.
    static func voice(pitch: Double, gain: Double, sampleRate: Double) -> [Float] {
        let count = Int(0.09 * sampleRate)
        let formants: [(Double, Double, Double)] = [(700, 130, 1), (1220, 70, 0.5), (2600, 160, 0.25)]
        var partials: [(Double, Double)] = []
        var k = 1.0
        while k * pitch < 4000 {
            let f = k * pitch
            let amplitude = formants.reduce(0) { sum, formant in
                let (center, width, level) = formant
                return sum + level / (1 + pow((f - center) / width, 2))
            }
            partials.append((f, amplitude))
            k += 1
        }
        let norm = max(0.001, partials.reduce(0) { $0 + $1.1 })
        return (0..<count).map { i in
            let t = Double(i) / sampleRate
            let envelope = min(1, Double(i) / max(1, 0.004 * sampleRate)) * exp(-t / 0.035)
            let body = partials.reduce(0) { $0 + $1.1 * sin(2 * Double.pi * $1.0 * t) } / norm
            return Float(gain * 1.6 * envelope * body)
        }
    }

    /// Wood block: two inharmonic partials with a fast decay.
    static func wood(_ frequency: Double, gain: Double, sampleRate: Double) -> [Float] {
        let count = Int(0.03 * sampleRate)
        return (0..<count).map { i in
            let t = Double(i) / sampleRate
            let envelope = min(1, Double(i) / max(1, 0.0003 * sampleRate)) * exp(-t / 0.006)
            let body = sin(2 * Double.pi * frequency * t) + 0.45 * sin(2 * Double.pi * frequency * 2.76 * t)
            return Float(gain * 0.7 * envelope * body)
        }
    }

    /// Electronic beep: a soft-edged square-ish tone, 25 ms.
    static func beep(_ frequency: Double, gain: Double, sampleRate: Double) -> [Float] {
        let count = Int(0.025 * sampleRate)
        let edge = Int(0.002 * sampleRate)
        return (0..<count).map { i in
            let t = Double(i) / sampleRate
            let envelope = min(1, Double(min(i, count - i)) / Double(max(1, edge)))
            let phase = sin(2 * Double.pi * frequency * t)
            return Float(gain * envelope * tanh(3 * phase) / tanh(3))
        }
    }

    /// A 15 ms sine burst with a 0.5 ms attack and exponential decay.
    public static func tone(_ frequency: Double, gain: Double, sampleRate: Double, duration: Double = 0.015) -> [Float] {
        let count = Int(duration * sampleRate)
        let attack = max(1, Int(0.0005 * sampleRate))
        return (0..<count).map { i in
            let t = Double(i) / sampleRate
            let envelope = (i < attack ? Double(i) / Double(attack) : 1) * exp(-t / (duration / 5))
            return Float(gain * envelope * sin(2 * Double.pi * frequency * t))
        }
    }

    func samples(for level: AccentLevel) -> [Float]? {
        switch level {
        case .strong: return strong
        case .normal: return normal
        case .soft: return soft
        case .off: return nil
        }
    }
}

/// Renders the clock into audio buffers without allocating (fixed voice pool) — usable from a real-time
/// render callback. Every tick, audible or not, is also handed to `onEvent` for the beat timeline (ME-12).
public final class MetronomeRenderer {
    public let clock: MetronomeClock
    public var sounds: ClickSounds
    public var volume: Float = 0.6

    private struct Voice { var level: AccentLevel; var track: Int; var position: Int; var startOffset: Int }
    private var voices: [Voice?]

    /// SND-3 event signals: one slot per sound. Buffers are set from outside under the host's lock and never
    /// released on the render thread — a finished event only stops advancing.
    private struct EventVoice { var samples: [Float] = []; var position = Int.max; var start: Int64 = 0 }
    private var events: [EventVoice] = Array(repeating: EventVoice(), count: EventSound.allCases.count)

    public init(clock: MetronomeClock, sounds: ClickSounds, maxVoices: Int = 32) {
        self.clock = clock
        self.sounds = sounds
        self.voices = Array(repeating: nil, count: maxVoices)
    }

    /// Mixes clicks into `output` (mono, `frameCount` frames) for the block starting at `sampleTime`.
    /// The buffer is overwritten.
    public func render(into output: UnsafeMutablePointer<Float>, frameCount: Int, sampleTime: Int64,
                       onEvent: (ClickEvent) -> Void = { _ in }) {
        output.update(repeating: 0, count: frameCount)
        clock.forEachEvent(from: sampleTime, frameCount: frameCount) { event in
            onEvent(event)
            guard !event.isSilent, event.level != .off else { return }
            if let slot = voices.firstIndex(where: { $0 == nil }) {
                voices[slot] = Voice(level: event.level, track: event.track, position: 0, startOffset: Int(event.sampleTime - sampleTime))
            }
        }
        for slot in voices.indices {
            guard var voice = voices[slot], let samples = sounds.samples(for: voice.level, track: voice.track) else { continue }
            var frame = voice.startOffset
            while frame < frameCount && voice.position < samples.count {
                output[frame] += samples[voice.position] * volume
                voice.position += 1
                frame += 1
            }
            voice.startOffset = 0
            voices[slot] = voice.position < samples.count ? voice : nil
        }
        renderEvents(into: output, frameCount: frameCount, sampleTime: sampleTime)
    }

    public func stopAllVoices() {
        for i in voices.indices { voices[i] = nil }
    }

    /// Plays `samples` (from `EventSounds.make`) at `sampleTime` on the output timeline; the click volume applies.
    public func scheduleEvent(_ sound: EventSound, samples: [Float], at sampleTime: Int64) {
        let slot = EventSound.allCases.firstIndex(of: sound)!
        events[slot] = EventVoice(samples: samples, position: 0, start: sampleTime)
    }

    /// True while an event signal is still sounding (tests, diagnostics).
    public var isPlayingEvent: Bool { events.contains { $0.position < $0.samples.count } }

    private func renderEvents(into output: UnsafeMutablePointer<Float>, frameCount: Int, sampleTime: Int64) {
        for slot in events.indices where events[slot].position < events[slot].samples.count {
            let first = max(0, Int(events[slot].start - sampleTime))
            guard first < frameCount else { continue }
            var frame = first
            var position = events[slot].position
            let samples = events[slot].samples
            while frame < frameCount && position < samples.count {
                output[frame] += samples[position] * volume
                position += 1
                frame += 1
            }
            events[slot].position = position
        }
    }
}
