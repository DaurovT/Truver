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
import TruverTheory

public struct TunerConfiguration: Sendable {
    public var sampleRate: Double
    /// A4 in effect for the current tuning (PR-5).
    public var a4: Double = 440
    /// Signal below this level is silence (TU-3, adjustable for the stage).
    public var noiseGateDB: Double = -55
    /// A rise of this many dB between hops is a new attack.
    public var attackRiseDB: Double = 9
    /// The first part of every note is ignored: the pitch is sharp right after the pluck (TU-5).
    public var attackIgnoreSeconds: Double = 0.04
    /// Analysis rate; at least 30 updates per second (NFR).
    public var hopSeconds: Double = 1.0 / 40
    /// Short window for speed, enough for E2 and above (TU-2).
    public var shortWindowSeconds: Double = 0.027
    public var shortMinFrequency: Double = 75
    /// Strings below this get a parallel long window (TU-2: "струны ниже E2").
    public var longWindowBelowFrequency: Double = 80
    public var yinThreshold: Double = 0.15
    public var maxAperiodicity: Double = 0.35
    public var octaveCheck = OctaveCheck()
    public var minFrequency: Double = 25
    public var maxFrequency: Double = 1500
    /// «В строю» switches on after `inTuneSeconds` within ±`inTuneCents` and off only beyond ±`inTuneExitCents`
    /// (hysteresis: the colour does not blink at the border — motion spec, «Тюнер»).
    public var inTuneCents: Double = 3
    public var inTuneExitCents: Double = 5
    public var inTuneSeconds: Double = 0.3
    public var medianLength: Int = 3
    /// Exponential smoothing with a variable weight (motion spec): fast far from the target, calm near it.
    public var smoothingFar: Double = 0.6
    public var smoothingNear: Double = 0.25
    public var smoothingSplitCents: Double = 15
    public var jumpResetCents: Double = 60
    /// TU-10: run the phase strobe alongside (only while the strobe view is on).
    public var strobe = false

    public init(sampleRate: Double) { self.sampleRate = sampleRate }
}

/// What the tuner screen shows (6.2.4).
public enum TunerDisplay: Equatable, Sendable {
    /// Below the noise gate: "Сыграйте струну".
    case idle
    /// A note is sounding but there is no reading yet, or its name is hidden until the long window
    /// answers (TU-4a): "слушаю".
    case listening
    /// Below 25 Hz or above the range.
    case outOfRange
    case reading(TunerReading)
}

public struct TunerReading: Equatable, Sendable {
    /// Smoothed frequency in Hz at the tuning's A4.
    public var frequency: Double
    public var pitch: Pitch
    public var target: TunerTarget
    /// The reading comes from the short window while the long one is still filling (TU-2).
    public var isProvisional: Bool
    /// «В строю» with hysteresis (on after 0.3 s within ±3 c, off beyond ±5 c).
    public var isInTune: Bool = false
}

public enum TunerEvent: Equatable, Sendable {
    /// Held within ±3 cents for 0.3 s (TU-8): mark on the string button.
    case stringTuned(StringRef)
    /// Every string of the tuning is tuned: "Готово" + haptic.
    case allStringsTuned
}

public struct TunerUpdate: Equatable, Sendable {
    /// Seconds of audio processed so far (end of the hop).
    public var time: Double
    public var display: TunerDisplay
    public var events: [TunerEvent]
    /// RMS level of the last hop in dBFS (input level indicator, AU-2).
    public var levelDB: Double = -160
    /// TU-10 phase strobe against the current target, when enabled.
    public var strobe: StrobeReading?
}

/// The tuner pipeline (TU-1…TU-8): filter → noise gate → attack detection and ignore → short and long YIN
/// windows → octave check → hiding → smoothing → target with string hold → in-tune tracking.
///
/// Not thread-safe: feed it from one thread (the audio analysis queue).
public final class PitchTracker {
    public private(set) var configuration: TunerConfiguration
    public var tuning: Tuning {
        didSet { tunedStrings = []; allTunedReported = false; rebuildPlan(); resetNote() }
    }
    public var mode: TunerMode {
        didSet { rebuildPlan(); resetNote() }
    }
    public private(set) var tunedStrings: Set<StringRef> = []

    private var filter: InputFilter
    private var buffer: [Float] = []
    private var capacity = 0
    private var totalSamples: Int64 = 0
    private var hopFill = 0
    private let hopLength: Int
    private let phaseStrobe: PhaseStrobe?

    private struct Frame { var window: Int; var maxLag: Int; var minFrequency: Double; var length: Int { window + maxLag } }
    private var primary = Frame(window: 1, maxLag: 2, minFrequency: 75)
    private var long: Frame?

    private var isSounding = false
    private var previousLevel = -160.0
    private var attackSample: Int64 = 0
    private var history: [Double] = []
    private var smoothed: Double?
    private var lock: (ref: StringRef, provisional: Bool)?
    private var usedLong = false
    private var inTune: (ref: StringRef, since: Int64)?
    private var latchedInTune: StringRef?
    private var allTunedReported = false
    private var pausedUntil: Int64 = 0
    private var lastDisplay: TunerDisplay = .idle

    public init(configuration: TunerConfiguration, tuning: Tuning, mode: TunerMode = .auto) {
        self.configuration = configuration
        self.tuning = tuning
        self.mode = mode
        self.hopLength = max(64, Int(configuration.sampleRate * configuration.hopSeconds))
        self.phaseStrobe = configuration.strobe ? PhaseStrobe(sampleRate: configuration.sampleRate) : nil
        let highest = tuning.coursePitches.map { $0.frequency(a4: configuration.a4) }.max() ?? 1000
        self.filter = InputFilter(sampleRate: configuration.sampleRate, highestFrequency: highest)
        rebuildPlan()
    }

    /// Ignores the input for `seconds` and keeps the last display: a haptic pulse is heard by the built-in
    /// microphone (motion spec, «Вибрация»: 50 ms around each pulse).
    public func pauseAnalysis(seconds: Double) {
        pausedUntil = max(pausedUntil, totalSamples + Int64(seconds * configuration.sampleRate))
    }

    /// Feeds samples (mono, any block size). Returns one update per analysis hop that completed.
    public func process(_ samples: [Float]) -> [TunerUpdate] {
        var input = samples
        filter.process(&input)
        var updates: [TunerUpdate] = []
        var index = 0
        while index < input.count {
            let take = min(hopLength - hopFill, input.count - index)
            phaseStrobe?.process(input[index..<(index + take)])
            buffer.append(contentsOf: input[index..<(index + take)])
            index += take
            hopFill += take
            totalSamples += Int64(take)
            if buffer.count > capacity { buffer.removeFirst(buffer.count - capacity) }
            if hopFill == hopLength {
                hopFill = 0
                var update = analyzeHop()
                if let phaseStrobe {
                    // The strobe follows the tuner's target; it measures only while a note is read.
                    if case .reading(let r) = update.display {
                        switch r.target {
                        case .string(_, let target, _): phaseStrobe.setTarget(frequency(target))
                        case .chromatic(let nearest, _, _): phaseStrobe.setTarget(frequency(nearest))
                        }
                        update.strobe = phaseStrobe.reading()
                    } else if case .idle = update.display {
                        phaseStrobe.setTarget(nil)
                    }
                }
                updates.append(update)
            }
        }
        return updates
    }

    // MARK: - Plan

    private func frequency(_ pitch: Pitch) -> Double { pitch.frequency(a4: configuration.a4) }

    private func rebuildPlan() {
        let sr = configuration.sampleRate
        func frame(minFrequency: Double, windowSeconds: Double) -> Frame {
            Frame(window: Int((windowSeconds * sr).rounded(.up)), maxLag: Int((sr / minFrequency).rounded(.up)) + 2,
                  minFrequency: minFrequency)
        }
        let lowest = tuning.coursePitches.map(frequency).min() ?? 82.4
        switch mode {
        case .manual(let course, let string):
            // ≥2 periods of the target; detection reaches a fifth below it ("подтяните на 2 тона").
            let target = frequency(tuning.openPitch(course: course, string: string))
            // Bass tunings reach F♯0 (23 Hz), under the usual floor.
            let minF = max(min(configuration.minFrequency, target * 0.9), target * pow(2, -7.0 / 12))
            primary = frame(minFrequency: minF, windowSeconds: max(2 / target, 1.2 / minF))
            long = nil
        case .auto, .chromatic:
            primary = frame(minFrequency: configuration.shortMinFrequency, windowSeconds: configuration.shortWindowSeconds)
            if lowest < configuration.longWindowBelowFrequency {
                let minF = max(min(configuration.minFrequency, lowest * 0.9), lowest * pow(2, -3.0 / 12))
                long = frame(minFrequency: minF, windowSeconds: 2 / lowest)
            } else {
                long = nil
            }
        }
        capacity = max(primary.length, long?.length ?? 0) + hopLength
    }

    private func resetNote() {
        history = []
        smoothed = nil
        lock = nil
        usedLong = false
        inTune = nil
        latchedInTune = nil
    }

    // MARK: - Analysis

    private func analyzeHop() -> TunerUpdate {
        let time = Double(totalSamples) / configuration.sampleRate
        let level = Level.rmsDB(buffer.suffix(hopLength))
        func update(_ display: TunerDisplay, _ events: [TunerEvent] = []) -> TunerUpdate {
            lastDisplay = display
            return TunerUpdate(time: time, display: display, events: events, levelDB: level)
        }

        defer { previousLevel = level }
        if totalSamples <= pausedUntil {
            return TunerUpdate(time: time, display: lastDisplay, events: [], levelDB: level)
        }
        guard level >= configuration.noiseGateDB else {
            if isSounding { isSounding = false; resetNote() }
            return update(.idle)
        }
        if !isSounding || level - previousLevel >= configuration.attackRiseDB {
            isSounding = true
            attackSample = totalSamples - Int64(hopLength)
            resetNote()
        }

        let since = Int(totalSamples - attackSample)
        let ignore = Int(configuration.attackIgnoreSeconds * configuration.sampleRate)
        guard since >= ignore + primary.length else { return update(.listening) }
        let longReady = long.map { since >= ignore + $0.length } ?? false

        let chosen = longReady ? long! : primary
        let frame = buffer.suffix(chosen.length).withUnsafeBufferPointer { ptr in
            YINFrame(samples: ptr, sampleRate: configuration.sampleRate, window: chosen.window, maxLag: chosen.maxLag)
        }
        let minLag = max(2, Int(configuration.sampleRate / configuration.maxFrequency))
        guard let raw = frame.estimate(minLag: minLag, threshold: configuration.yinThreshold),
              raw.aperiodicity <= configuration.maxAperiodicity else { return update(.listening) }
        let estimate = configuration.octaveCheck.apply(raw, frame: frame, minFrequency: chosen.minFrequency).estimate
        let f = estimate.frequency
        guard f >= min(configuration.minFrequency, chosen.minFrequency), f <= configuration.maxFrequency else { return update(.outOfRange) }

        // TU-4a: while the long window is not ready, hide the name if a string sits at f/2 or f/3.
        if long != nil, !longReady {
            let found = Pitch(frequency: f, a4: configuration.a4).cents
            let suspicious = tuning.coursePitches.contains { string in
                [1200.0, 1902.0].contains { abs(found - $0 - string.cents) <= 150 }
            }
            if suspicious { return update(.listening) }
        }

        // The first long-window frame may correct a provisional capture without a new attack (TU-4a).
        if longReady && !usedLong {
            usedLong = true
            if lock?.provisional == true { lock = nil }
        }

        // Smoothing (TU-5): the first reading is shown immediately, then median of 3 + exponential.
        let cents = Pitch(frequency: f, a4: configuration.a4).cents
        if let s = smoothed, abs(cents - s) > configuration.jumpResetCents {
            history = []
            smoothed = nil
        }
        history.append(cents)
        if history.count > configuration.medianLength { history.removeFirst() }
        let median = history.sorted()[history.count / 2]
        let alpha = abs(median - referenceCents(near: median)) > configuration.smoothingSplitCents
            ? configuration.smoothingFar : configuration.smoothingNear
        smoothed = smoothed.map { $0 + alpha * (median - $0) } ?? cents
        let pitch = Pitch(cents: smoothed!)

        let target = resolveTarget(pitch, provisional: long != nil && !longReady)
        let events = trackInTune(target)
        var isInTune = false
        if case let .string(ref, _, _) = target { isInTune = latchedInTune == ref }
        let reading = TunerReading(frequency: pitch.frequency(a4: configuration.a4), pitch: pitch, target: target,
                                   isProvisional: long != nil && !longReady, isInTune: isInTune)
        return update(.reading(reading), events)
    }

    /// The pitch the needle is heading for: the held or selected string, else the nearest note.
    private func referenceCents(near cents: Double) -> Double {
        if case let .manual(course, string) = mode { return tuning.openPitch(course: course, string: string).cents }
        if let lock { return tuning.openPitch(course: lock.ref.course, string: lock.ref.string).cents }
        return (cents / 100).rounded() * 100
    }

    private func resolveTarget(_ pitch: Pitch, provisional: Bool) -> TunerTarget {
        guard case .auto = mode else { return TunerTargeting.resolve(pitch, tuning: tuning, mode: mode) }
        if let lock {
            let target = tuning.openPitch(course: lock.ref.course, string: lock.ref.string)
            let deviation = pitch.cents - target.cents
            if abs(deviation) <= TunerTargeting.autoCaptureCents {
                return .string(lock.ref, target: target, deviationCents: deviation)
            }
            self.lock = nil
        }
        let result = TunerTargeting.resolve(pitch, tuning: tuning, mode: .auto)
        if case let .string(ref, _, _) = result { lock = (ref, provisional) }
        return result
    }

    private func trackInTune(_ target: TunerTarget) -> [TunerEvent] {
        guard case let .string(ref, _, deviation) = target else {
            inTune = nil
            latchedInTune = nil
            return []
        }
        if latchedInTune == ref {
            // Hysteresis: once in tune, stay until the wide threshold is crossed.
            if abs(deviation) > configuration.inTuneExitCents {
                latchedInTune = nil
                inTune = nil
            }
            return []
        }
        latchedInTune = nil
        guard abs(deviation) <= configuration.inTuneCents else {
            inTune = nil
            return []
        }
        guard let current = inTune, current.ref == ref else {
            inTune = (ref, totalSamples)
            return []
        }
        let held = Double(totalSamples - current.since) / configuration.sampleRate
        guard held >= configuration.inTuneSeconds else { return [] }
        latchedInTune = ref
        guard !tunedStrings.contains(ref) else { return [] }
        tunedStrings.insert(ref)
        var events: [TunerEvent] = [.stringTuned(ref)]
        let total = tuning.openCents.reduce(0) { $0 + $1.count }
        if tunedStrings.count == total && !allTunedReported {
            allTunedReported = true
            events.append(.allStringsTuned)
        }
        return events
    }
}
