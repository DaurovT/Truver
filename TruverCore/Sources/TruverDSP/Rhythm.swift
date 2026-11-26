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

// MARK: - Grades and bands (SM-4)

public enum RhythmGrade: String, Sendable, CaseIterable {
    /// «точно»
    case exact
    /// «хорошо»
    case good
    /// «неточно»
    case inaccurate
    /// «мимо» (still bound to the expected note, within half the subdivision)
    case off
    /// An attack with no expected note within half a subdivision (SM-2).
    case extra
    /// An expected note without an attack (SM-2).
    case missing
    /// Sound was there but no reliable attack or pitch (SM-10): neither a hit nor an error.
    case unrecognized
}

/// Upper limits (absolute deviation, seconds) of each grade for one subdivision length.
public struct GradeBands: Equatable, Sendable {
    public var exact: Double
    public var good: Double
    public var inaccurate: Double
    /// Half the subdivision: beyond it the attack belongs to no note.
    public var half: Double

    public func grade(_ deviation: Double) -> RhythmGrade {
        let d = abs(deviation)
        if d <= exact { return .exact }
        if d <= good { return .good }
        if d <= inaccurate { return .inaccurate }
        if d <= half { return .off }
        return .extra
    }
}

/// SM-4 thresholds. Values are the PRD's starting points; they are to be checked on live playing.
public struct RhythmThresholds: Sendable {
    /// Lower bound of «точно»: twice the measured detector error (SM-1 measured ≤ 0.5 ms on synthetic picks; the
    /// PRD's 6 ms stays until live recordings say otherwise).
    public var pmin = 0.006
    public var exactCap = 0.010, goodCap = 0.025, inaccurateCap = 0.050
    public var exactFraction = 0.08, goodFraction = 0.20, inaccurateFraction = 0.35
    /// Below this subdivision the rhythm is not graded (the metronome still plays).
    public var minSubdivision = 0.040

    public init() {}

    /// Bands for a subdivision of `interval` seconds; nil when the subdivision is too short to grade.
    /// Each band is at least as wide as the previous one (SM-4: monotonic).
    public func bands(subdivision interval: Double) -> GradeBands? {
        guard interval >= minSubdivision else { return nil }
        let exact = max(pmin, min(exactCap, exactFraction * interval))
        let good = max(exact, min(goodCap, goodFraction * interval))
        let half = interval / 2
        let inaccurate = min(half, max(good, min(inaccurateCap, inaccurateFraction * interval)))
        return GradeBands(exact: exact, good: good, inaccurate: inaccurate, half: half)
    }
}

// MARK: - Notes

/// A note the exercise expects, on the input timeline (seconds).
public struct ExpectedNote: Equatable, Sendable {
    public var time: Double
    public var bar: Int
    public var beat: Int
    public var tick: Int
    /// Length of the subdivision this note sits on (seconds) — sets the grade bands.
    public var interval: Double
    /// Expected pitch for the note check (SM-5), nil = rhythm only.
    public var pitch: Pitch?
    /// The click was silent in this bar (gap bars).
    public var silentBar: Bool

    public init(time: Double, bar: Int, beat: Int, tick: Int = 0, interval: Double, pitch: Pitch? = nil, silentBar: Bool = false) {
        self.time = time
        self.bar = bar
        self.beat = beat
        self.tick = tick
        self.interval = interval
        self.pitch = pitch
        self.silentBar = silentBar
    }
}

/// An attack the detector found, with the pitch the tuner heard right after it (nil = not recognised).
public struct PlayedNote: Equatable, Sendable {
    public var time: Double
    public var pitch: Pitch?

    public init(time: Double, pitch: Pitch? = nil) {
        self.time = time
        self.pitch = pitch
    }
}

public struct GradedNote: Equatable, Sendable {
    public var expected: ExpectedNote?
    public var played: PlayedNote?
    /// played − expected, seconds (negative = rushed).
    public var deviation: Double?
    public var grade: RhythmGrade
    /// SM-5: nil when not checked (no expected pitch or the pitch was not recognised).
    public var wrongNote: Bool?
}

public struct PitchCheck: Sendable {
    /// Semitone tolerance (SM-5: "с точностью до полутона").
    public var toleranceCents: Double = 50
    /// "Гамма в любой октаве".
    public var anyOctave: Bool = false

    public init(anyOctave: Bool = false) { self.anyOctave = anyOctave }

    public func isWrong(played: Pitch, expected: Pitch) -> Bool {
        var difference = played.cents - expected.cents
        if anyOctave {
            difference = difference.truncatingRemainder(dividingBy: 1200)
            if difference > 600 { difference -= 1200 }
            if difference < -600 { difference += 1200 }
        }
        return abs(difference) > toleranceCents
    }
}

// MARK: - Grader (SM-2, SM-3, SM-5, SM-10)

public enum RhythmGrader {
    /// Binds attacks to expected notes and grades them.
    /// - Each attack goes to the nearest expected note; farther than half its subdivision → `extra`.
    /// - If several attacks claim one note, the closest wins and the others are `extra`.
    /// - An expected note without an attack is `missing`, or `unrecognized` when `isSounding(time)` says there
    ///   was sound (muted notes, fast legato: SM-10).
    public static func grade(expected: [ExpectedNote],
                             played: [PlayedNote],
                             thresholds: RhythmThresholds = RhythmThresholds(),
                             pitchCheck: PitchCheck? = nil,
                             isSounding: ((Double) -> Bool)? = nil) -> [GradedNote] {
        guard !expected.isEmpty else { return played.map { GradedNote(expected: nil, played: $0, deviation: nil, grade: .extra) } }
        let sortedExpected = expected.sorted { $0.time < $1.time }

        var claims: [Int: Int] = [:]          // expected index → played index
        var extras: [Int] = []
        for (p, note) in played.enumerated() {
            let e = nearest(note.time, in: sortedExpected)
            let target = sortedExpected[e]
            guard abs(note.time - target.time) <= target.interval / 2 else { extras.append(p); continue }
            if let other = claims[e] {
                if abs(note.time - target.time) < abs(played[other].time - target.time) {
                    extras.append(other)
                    claims[e] = p
                } else {
                    extras.append(p)
                }
            } else {
                claims[e] = p
            }
        }

        var result: [GradedNote] = []
        for (e, target) in sortedExpected.enumerated() {
            guard let p = claims[e] else {
                let heard = isSounding?(target.time) ?? false
                result.append(GradedNote(expected: target, played: nil, deviation: nil, grade: heard ? .unrecognized : .missing))
                continue
            }
            let note = played[p]
            let deviation = note.time - target.time
            let grade = thresholds.bands(subdivision: target.interval)?.grade(deviation) ?? .unrecognized
            var wrong: Bool?
            if let check = pitchCheck, let expectedPitch = target.pitch, let heard = note.pitch {
                wrong = check.isWrong(played: heard, expected: expectedPitch)
            }
            result.append(GradedNote(expected: target, played: note, deviation: deviation, grade: grade, wrongNote: wrong))
        }
        for p in extras {
            result.append(GradedNote(expected: nil, played: played[p], deviation: nil, grade: .extra))
        }
        return result.sorted { ($0.expected?.time ?? $0.played?.time ?? 0) < ($1.expected?.time ?? $1.played?.time ?? 0) }
    }

    private static func nearest(_ time: Double, in notes: [ExpectedNote]) -> Int {
        var lo = 0, hi = notes.count - 1
        while lo < hi {
            let mid = (lo + hi) / 2
            if notes[mid].time < time { lo = mid + 1 } else { hi = mid }
        }
        if lo > 0 && abs(notes[lo - 1].time - time) <= abs(notes[lo].time - time) { return lo - 1 }
        return lo
    }
}

// MARK: - Bar statistics (SM-3, SM-8)

public struct BarStats: Equatable, Sendable {
    public var bar: Int
    /// Mean signed deviation (s): the habit to rush (−) or drag (+).
    public var meanDeviation: Double?
    /// Standard deviation of the deviations (s): stability.
    public var spread: Double?
    /// Share of «точно + хорошо» among graded notes (unrecognized excluded, SM-8).
    public var accurateShare: Double
    public var graded: Int
    public var missing: Int
    public var extra: Int
    public var wrongNotes: Int
    public var unrecognizedShare: Double
    /// SM-8: a bar with more than 30 % unrecognized notes counts neither up nor down.
    public var isCounted: Bool
    /// Mean deviation per beat (for the heat map, PL-4).
    public var perBeat: [Int: Double]
}

public enum RhythmStats {
    public static func bars(_ notes: [GradedNote], maxUnrecognizedShare: Double = 0.3) -> [BarStats] {
        let byBar = Dictionary(grouping: notes.filter { $0.expected != nil }) { $0.expected!.bar }
        let extrasByBar = Dictionary(grouping: notes.filter { $0.grade == .extra && $0.played != nil }) { note -> Int in
            // Attribute an extra attack to the bar of the expected note before it.
            let t = note.played!.time
            return notes.compactMap(\.expected).filter { $0.time <= t }.last?.bar ?? 0
        }
        return byBar.keys.sorted().map { bar in
            let items = byBar[bar]!
            let unrecognized = items.filter { $0.grade == .unrecognized }.count
            let graded = items.filter { [.exact, .good, .inaccurate, .off, .missing].contains($0.grade) }
            let accurate = graded.filter { $0.grade == .exact || $0.grade == .good }.count
            let deviations = items.compactMap(\.deviation)
            let mean = deviations.isEmpty ? nil : deviations.reduce(0, +) / Double(deviations.count)
            let spread = mean.map { m in (deviations.map { ($0 - m) * ($0 - m) }.reduce(0, +) / Double(deviations.count)).squareRoot() }
            var perBeat: [Int: Double] = [:]
            for (beat, group) in Dictionary(grouping: items.filter { $0.deviation != nil }, by: { $0.expected!.beat }) {
                perBeat[beat] = group.compactMap(\.deviation).reduce(0, +) / Double(group.count)
            }
            let unrecognizedShare = items.isEmpty ? 0 : Double(unrecognized) / Double(items.count)
            return BarStats(bar: bar, meanDeviation: mean, spread: spread,
                            accurateShare: graded.isEmpty ? 0 : Double(accurate) / Double(graded.count),
                            graded: graded.count,
                            missing: items.filter { $0.grade == .missing }.count,
                            extra: extrasByBar[bar]?.count ?? 0,
                            wrongNotes: items.filter { $0.wrongNote == true }.count,
                            unrecognizedShare: unrecognizedShare,
                            isCounted: unrecognizedShare <= maxUnrecognizedShare && !graded.isEmpty,
                            perBeat: perBeat)
        }
    }

    /// SM-3 for gap bars: mean deviation of the notes on the first beat after the click returns, i.e. how far the
    /// tempo drifted during the silence. Nil when there was no silent bar followed by a clicked one.
    public static func silenceDrift(_ notes: [GradedNote]) -> Double? {
        let expected = notes.compactMap(\.expected)
        let silentBars = Set(expected.filter(\.silentBar).map(\.bar))
        let returnBars = Set(expected.filter { !$0.silentBar && silentBars.contains($0.bar - 1) }.map(\.bar))
        let firstNotes = notes.filter { note in
            guard let e = note.expected, let d = note.deviation, returnBars.contains(e.bar), e.beat == 0 else { return false }
            return d.isFinite
        }
        guard !firstNotes.isEmpty else { return nil }
        return firstNotes.compactMap(\.deviation).reduce(0, +) / Double(firstNotes.count)
    }
}

// MARK: - Adaptive tempo (SM-8, SM-9)

public struct AdaptiveTempo: Sendable {
    public enum Decision: Equatable, Sendable { case stepUp, stepDown, hold }

    /// N clean bars in a row → up.
    public var cleanBarsToStepUp: Int
    public var upShare = 0.9
    public var downShare = 0.7
    public var failingBarsToStepDown = 2

    public private(set) var cleanInARow = 0
    public private(set) var failingInARow = 0
    /// SM-9: the highest tempo at which the step-up rule was met.
    public private(set) var ceiling: Double?

    public init(cleanBarsToStepUp: Int = 4, ceiling: Double? = nil) {
        self.cleanBarsToStepUp = cleanBarsToStepUp
        self.ceiling = ceiling
    }

    /// Feeds one finished bar played at `tempo`.
    public mutating func record(_ bar: BarStats, tempo: Double) -> Decision {
        guard bar.isCounted else { return .hold }   // more than 30 % unrecognized: neither up nor down
        let clean = bar.accurateShare >= upShare && bar.missing == 0 && bar.wrongNotes == 0
        let failing = bar.accurateShare < downShare
        if clean {
            cleanInARow += 1
            failingInARow = 0
        } else if failing {
            failingInARow += 1
            cleanInARow = 0
        } else {
            cleanInARow = 0
            failingInARow = 0
        }
        if cleanInARow >= cleanBarsToStepUp {
            cleanInARow = 0
            ceiling = max(ceiling ?? tempo, tempo)
            return .stepUp
        }
        if failingInARow >= failingBarsToStepDown {
            failingInARow = 0
            return .stepDown
        }
        return .hold
    }

    /// SM-9: the next session starts 10 % below the ceiling.
    public static func nextSessionStart(ceiling: Double) -> Double {
        (ceiling * 0.9).rounded().clamped(to: MeterSettings.tempoRange)
    }
}

// MARK: - Expected grid from the metronome (ME-12)

extension ExpectedNote {
    /// One expected note per tick of the metronome timeline (the exercise plays the subdivision it clicks).
    /// `time(of:)` converts a tick to the input timeline in seconds (output latency and loopback offset applied
    /// by the caller).
    public static func grid(from ticks: [ClickEvent], time: (ClickEvent) -> Double,
                            pitch: ((ClickEvent) -> Pitch?)? = nil) -> [ExpectedNote] {
        ticks.map { tick in
            ExpectedNote(time: time(tick), bar: tick.bar, beat: tick.beat, tick: tick.tick,
                         interval: 60 / tick.bpm / Double(max(1, tick.subdivision)),
                         pitch: pitch?(tick), silentBar: tick.isSilent)
        }
    }
}
