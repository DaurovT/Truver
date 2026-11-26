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

/// Accent of a beat (ME-3): tap on a beat cycles strong → normal → soft → off.
public enum AccentLevel: Int, CaseIterable, Sendable, Codable, Comparable {
    case off, soft, normal, strong

    public static func < (lhs: AccentLevel, rhs: AccentLevel) -> Bool { lhs.rawValue < rhs.rawValue }

    public var next: AccentLevel {
        switch self {
        case .strong: return .normal
        case .normal: return .soft
        case .soft: return .off
        case .off: return .strong
        }
    }
}

/// Bar model of the metronome (ME-2, ME-3).
public struct MeterSettings: Hashable, Sendable, Codable {
    public static let tempoRange: ClosedRange<Double> = 20...400
    public static let subdivisionRange: ClosedRange<Int> = 1...9
    public static let swingRange: ClosedRange<Double> = 0.5...0.75

    /// Beats per minute of the denominator's note value.
    public var bpm: Double { didSet { bpm = bpm.clamped(to: MeterSettings.tempoRange) } }
    public var numerator: Int
    public var denominator: Int
    /// "2+2+3"; nil = no grouping. Must sum to `numerator`.
    public var grouping: [Int]?
    public var accents: [AccentLevel]
    public var subdivision: Int { didSet { subdivision = subdivision.clamped(to: MeterSettings.subdivisionRange) } }
    /// Position of the second note of each pair: 0.5 straight … 0.667 triplet swing … 0.75. Even subdivisions only.
    public var swing: Double { didSet { swing = swing.clamped(to: MeterSettings.swingRange) } }
    /// A rhythmic figure instead of an even subdivision (16-16-8, dotted, triplet shuffle, half / whole notes);
    /// nil = `subdivision` even clicks. Set together with `subdivision = rhythm.grid` (the sheet shows that number).
    public var rhythm: BeatRhythm?
    /// Per-beat figures (Soundbrenner-style: «1-я — восьмые, 3-я — триоль»); nil entries follow `rhythm`.
    /// One-beat figures only.
    public var beatRhythms: [BeatRhythm?]?
    /// ME-8: a second track with its own sound — a polyrhythm or a polymeter against the main pulse.
    public var poly: PolyTrack?

    /// The figure of `beat`: its own, else the common one.
    public func rhythm(forBeat beat: Int) -> BeatRhythm? {
        if let own = beatRhythms, beat < own.count, let r = own[beat] { return r }
        return rhythm
    }

    public init(bpm: Double = 120, numerator: Int = 4, denominator: Int = 4, grouping: [Int]? = nil,
                accents: [AccentLevel]? = nil, subdivision: Int = 1, swing: Double = 0.5) {
        self.bpm = bpm.clamped(to: MeterSettings.tempoRange)
        self.numerator = max(1, numerator)
        self.denominator = denominator
        self.grouping = grouping
        self.accents = accents ?? MeterSettings.defaultAccents(numerator: max(1, numerator), grouping: grouping)
        self.subdivision = subdivision.clamped(to: MeterSettings.subdivisionRange)
        self.swing = swing.clamped(to: MeterSettings.swingRange)
    }

    /// Strong first beat, normal on group starts, soft inside groups; without grouping all other beats normal.
    public static func defaultAccents(numerator: Int, grouping: [Int]?) -> [AccentLevel] {
        guard let grouping, grouping.reduce(0, +) == numerator else {
            return [.strong] + Array(repeating: .normal, count: max(0, numerator - 1))
        }
        var result: [AccentLevel] = []
        for group in grouping {
            for i in 0..<group { result.append(i == 0 ? .normal : .soft) }
        }
        result[0] = .strong
        return result
    }

    /// Error shown in the meter sheet (6.2.6), nil when valid.
    public var validationError: String? {
        if let grouping, grouping.reduce(0, +) != numerator { return "groupingSum" }
        if accents.count != numerator { return "accentCount" }
        return nil
    }

    /// Swing is offered only for even subdivisions (6.2.6).
    public var isSwingAvailable: Bool { subdivision % 2 == 0 }

    public var beatSeconds: Double { 60 / bpm }
}

// MARK: - Training modes (ME-6), one per group (6.1 п. 7)

public enum TempoInterval: Hashable, Sendable, Codable {
    case bars(Int)
    case seconds(Double)
}

/// Tempo group.
public enum TempoMode: Hashable, Sendable, Codable {
    /// Разгон: +step every interval up to the target; then the tempo holds (6.1 п. 10).
    case speedUp(step: Double, every: TempoInterval, target: Double)
    /// Два вперёд, один назад: +2N, −N, +2N … every `everyBars` bars up to the target.
    case twoForwardOneBack(step: Double, everyBars: Int, target: Double)
    /// Быстро / медленно: `everyBars` bars at the slow tempo, then `everyBars` at the fast one, in a loop (P1).
    case fastSlow(slow: Double, fast: Double, everyBars: Int)
    /// Карта песни: sections with their own tempo, meter and length; optional one-bar count-in, loop or stop.
    case songMap(sections: [SongSection], loop: Bool, countIn: Bool)
}

/// One part of a song map («Куплет · 140 · 4/4 · 8 тактов»).
public struct SongSection: Hashable, Sendable, Codable, Identifiable {
    public var id: UUID
    public var name: String
    public var bpm: Double
    public var numerator: Int
    public var denominator: Int
    public var bars: Int

    public init(id: UUID = UUID(), name: String, bpm: Double, numerator: Int = 4, denominator: Int = 4, bars: Int = 8) {
        self.id = id
        self.name = name
        self.bpm = bpm
        self.numerator = max(1, numerator)
        self.denominator = denominator
        self.bars = max(1, bars)
    }
}

/// ME-8 second track. `.rhythm`: `count` even pulses over `span` beats (nil — the bar): 3 against 4, 5 against 4.
/// `.meter`: a click every `count` beats, running across bar lines: 3/4 against 4/4 meets again after 12 beats.
public struct PolyTrack: Hashable, Sendable, Codable {
    public enum Kind: String, Hashable, Sendable, Codable { case rhythm, meter }
    public var kind: Kind
    public var count: Int
    public var span: Int?

    public init(kind: Kind, count: Int, span: Int? = nil) {
        self.kind = kind
        self.count = max(1, count)
        self.span = span.map { max(1, $0) }
    }
}

/// Subdivision group.
public enum SubdivisionMode: Hashable, Sendable, Codable {
    /// Лесенка делений: quarters → eighths → triplets → sixteenths in a loop.
    case ladder(steps: [Int], barsPerStep: Int)

    public static let standardLadder = SubdivisionMode.ladder(steps: [1, 2, 3, 4], barsPerStep: 2)
}

public enum ClickPattern: String, Hashable, Sendable, Codable {
    /// Only beats 2 and 4 (every second beat).
    case backbeats
    /// Only the "and" between beats.
    case offbeats
    /// Only beat 1.
    case downbeat
}

/// Sound group.
public enum SoundMode: Hashable, Sendable, Codable {
    /// Перенос щелчка.
    case displacedClick(ClickPattern)
    /// Пропадающие такты: `on` bars with clicks, `off` bars silent; `off` grows by `offGrowth` per cycle up to `maxOff`.
    case gapBars(on: Int, off: Int, offGrowth: Int, maxOff: Int)
    /// Случайный пропуск: every beat except the first of the bar goes silent with `probability` (0…1, P1).
    case randomMute(probability: Double)
}

/// The active modes: at most one per group by construction (6.1 п. 7).
public struct TrainingModes: Hashable, Sendable, Codable {
    public var tempo: TempoMode?
    public var subdivision: SubdivisionMode?
    public var sound: SoundMode?

    public init(tempo: TempoMode? = nil, subdivision: SubdivisionMode? = nil, sound: SoundMode? = nil) {
        self.tempo = tempo
        self.subdivision = subdivision
        self.sound = sound
    }

    public static let none = TrainingModes()
}

// MARK: - Tap tempo (ME-2)

/// Average of the last 4–8 taps; a pause longer than 2 s starts a new measurement.
public struct TapTempo: Sendable {
    public var minimumTaps = 4
    public var maximumTaps = 8
    public var resetAfter: Double = 2
    private var taps: [Double] = []

    public init() {}

    /// Registers a tap at `time` seconds; returns the tempo once there are enough taps.
    public mutating func tap(at time: Double) -> Double? {
        if let last = taps.last, time - last > resetAfter || time <= last { taps = [] }
        taps.append(time)
        if taps.count > maximumTaps { taps.removeFirst(taps.count - maximumTaps) }
        guard taps.count >= minimumTaps else { return nil }
        let interval = (taps.last! - taps.first!) / Double(taps.count - 1)
        return (60 / interval).clamped(to: MeterSettings.tempoRange)
    }

    public mutating func reset() { taps = [] }
}

// MARK: - Flash limiting (6.1 п. 9)

public enum FlashRule: Hashable, Sendable {
    case everyBeat
    case strongBeats
    case firstBeat
    /// Only the first beat of every n-th bar.
    case everyNthBar(Int)
}

public enum FlashPolicy {
    public static let maxFlashesPerSecond = 3.0

    /// Densest rule that keeps flashes at or below 3 per second.
    public static func rule(for settings: MeterSettings) -> FlashRule {
        let beatsPerSecond = settings.bpm / 60
        if beatsPerSecond <= maxFlashesPerSecond { return .everyBeat }
        let barsPerSecond = beatsPerSecond / Double(settings.numerator)
        let strong = Double(settings.accents.filter { $0 == .strong }.count)
        if strong * barsPerSecond <= maxFlashesPerSecond, strong < Double(settings.numerator) { return .strongBeats }
        if barsPerSecond <= maxFlashesPerSecond { return .firstBeat }
        return .everyNthBar(Int((barsPerSecond / maxFlashesPerSecond).rounded(.up)))
    }

    public static func flashes(_ event: ClickEvent, rule: FlashRule, accents: [AccentLevel]) -> Bool {
        guard !event.isSilent, event.tick == 0, event.level != .off else { return false }
        switch rule {
        case .everyBeat: return true
        case .strongBeats: return accents.indices.contains(event.beat) && accents[event.beat] == .strong
        case .firstBeat: return event.beat == 0
        case .everyNthBar(let n): return event.beat == 0 && event.bar % n == 0
        }
    }
}

extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self { min(max(self, range.lowerBound), range.upperBound) }
}

/// A rhythmic figure of the metronome (user request: quick note values «как в Soundbrenner» and as many figures as
/// possible). `grid` equal steps over `span` beats, `onsets` — the steps that click. `span` 1 = one beat (16-16-8,
/// triplets); 2…4 = figures over several beats (syncopations, quarter triplets, clave); 0 = the whole bar.
public struct BeatRhythm: Hashable, Sendable, Codable, Identifiable {
    public var id: String
    public var grid: Int
    public var onsets: [Int]
    public var span: Int
    /// Section of the picker.
    public var group: BeatRhythmGroup

    public init(id: String, grid: Int, onsets: [Int], span: Int = 1, group: BeatRhythmGroup = .values) {
        self.id = id
        self.grid = max(1, grid)
        self.onsets = Array(Set(onsets.filter { $0 >= 0 && $0 < max(1, grid) })).sorted()
        self.span = span
        self.group = group
    }

    enum CodingKeys: String, CodingKey { case id, grid, onsets, span, group }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(id: try c.decode(String.self, forKey: .id), grid: try c.decode(Int.self, forKey: .grid),
                  onsets: try c.decode([Int].self, forKey: .onsets), span: try c.decodeIfPresent(Int.self, forKey: .span) ?? 1,
                  group: try c.decodeIfPresent(BeatRhythmGroup.self, forKey: .group) ?? .values)
    }

    /// Beats the figure covers in a bar of `numerator` beats.
    public func beats(numerator: Int) -> Int { span == 0 ? max(1, numerator) : span }

    /// Lengths of the clicked notes in grid steps (the last one runs to the end of the figure).
    public var durations: [Int] {
        onsets.enumerated().map { i, o in (i + 1 < onsets.count ? onsets[i + 1] : grid) - o }
    }

    /// Steps per beat (1.5 for quarter triplets, 0.75 for half-note triplets).
    public var stepsPerBeat: Double { Double(grid) / Double(span == 0 ? 4 : span) }

    /// Tuplet number over the figure: when a beat is not split in a power of two (3, 5, 6, 7, 9; quarter triplets).
    public var tuplet: Int? {
        let x = stepsPerBeat
        let powers: [Double] = [0.25, 0.5, 1, 2, 4, 8, 16]
        if powers.contains(where: { abs($0 - x) < 1e-9 }) { return nil }
        // The number of notes in one tuplet group: grid / span reduced (3 over 2 → 3, 6 per beat → 6).
        var g = grid, sp = span == 0 ? 4 : span
        func gcd(_ a: Int, _ b: Int) -> Int { b == 0 ? a : gcd(b, a % b) }
        let d = gcd(g, sp); g /= d; sp /= d
        return g
    }

    /// Over the figure: «3», «6» for tuplets, «5:3» for polyrhythms (5 notes in 3 beats differ from a quintuplet).
    public var tupletLabel: String? {
        guard let n = tuplet else { return nil }
        return group == .polyrhythm ? "\(onsets.count):\(span == 0 ? 4 : span)" : "\(n)"
    }

    /// Even subdivision of one beat without rests.
    public var isPlain: Bool { span == 1 && onsets == Array(0..<grid) }

    /// Click positions in beats from the figure's start (for the clock and equality of figures).
    public func positions(numerator: Int = 4) -> [Double] {
        let b = Double(beats(numerator: numerator))
        return onsets.map { Double($0) * b / Double(grid) }
    }

    /// «16-16-8», «8.-16», «п-8», «8-4-8»: durations in note values (rest «п» before a late start).
    public var shortName: String {
        let spb = stepsPerBeat
        let nominal = pow(2, floor(log2(max(0.25, spb))))      // tuplets are named as the plain value they replace
        func value(_ steps: Int) -> String {
            let beats = Double(steps) / nominal                   // length in nominal quarter notes
            let table: [(Double, String)] = [(4, "1"), (3, "2."), (2, "2"), (1.5, "4."), (1, "4"), (0.75, "8."), (0.5, "8"),
                                             (0.375, "16."), (0.25, "16"), (0.125, "32")]
            if let exact = table.first(where: { abs($0.0 - beats) < 1e-6 }) { return exact.1 }
            // Lengths without a single note value are tied notes: 1.25 → «4+16», 2.5 → «2+8».
            var rest = beats, parts: [String] = []
            for (len, name) in table where rest > 1e-6 && parts.count < 3 {
                while rest + 1e-6 >= len && parts.count < 3 { parts.append(name); rest -= len }
            }
            return parts.joined(separator: "+")
        }
        var parts = durations.map(value)
        if let first = onsets.first, first > 0 { parts.insert("п" + (value(first) == "8" ? "" : value(first)), at: 0) }
        return parts.joined(separator: "-")
    }
}

public enum BeatRhythmGroup: String, CaseIterable, Sendable, Codable {
    case values, tuplets, sixteenths, triplets, sextuplets, thirtySeconds, syncopation, latin, polyrhythm

    public var title: String {
        switch self {
        case .values: return "Длительности"
        case .tuplets: return "Триоли и группы"
        case .sixteenths: return "Шестнадцатые"
        case .triplets: return "Триольные фигуры"
        case .sextuplets: return "Секстоли"
        case .thirtySeconds: return "Тридцать вторые"
        case .syncopation: return "Синкопы на две доли"
        case .latin: return "Латина и грув на такт"
        case .polyrhythm: return "Полиритмы и смещения"
        }
    }
}

public enum BeatRhythms {
    /// Every figure of the picker, without duplicates (a figure equal to a simpler one — 2 of 4 sixteenths on the
    /// beat and the half — is kept only once, as the simpler).
    public static let all: [BeatRhythm] = build()

    public static func rhythm(id: String) -> BeatRhythm? { all.first { $0.id == id } }

    public static func figures(in group: BeatRhythmGroup) -> [BeatRhythm] { all.filter { $0.group == group } }

    private static func build() -> [BeatRhythm] {
        var list: [BeatRhythm] = []
        var seen = Set<String>()
        func key(_ r: BeatRhythm) -> String {
            // Positions rounded to 1/10000 of a beat (was `String(format: "%.4f")` — not in FoundationEssentials).
            "\(r.span):" + r.positions().map { String(Int(($0 * 10_000).rounded())) }.joined(separator: ",")
        }
        func add(_ r: BeatRhythm) {
            guard !r.onsets.isEmpty, seen.insert(key(r)).inserted else { return }
            list.append(r)
        }
        func subsets(_ n: Int) -> [[Int]] {
            (1..<(1 << n)).map { mask in (0..<n).filter { mask & (1 << $0) != 0 } }
        }

        // Plain values.
        add(BeatRhythm(id: "whole", grid: 1, onsets: [0], span: 0))
        add(BeatRhythm(id: "half", grid: 1, onsets: [0], span: 2))
        add(BeatRhythm(id: "quarter", grid: 1, onsets: [0]))
        add(BeatRhythm(id: "eighths", grid: 2, onsets: [0, 1]))
        add(BeatRhythm(id: "sixteenths", grid: 4, onsets: [0, 1, 2, 3]))
        add(BeatRhythm(id: "thirtyseconds", grid: 8, onsets: Array(0..<8)))

        // Tuplets and odd groups.
        let tuplets: [(String, Int, Int)] = [("half-triplets", 3, 4), ("quarter-triplets", 3, 2), ("triplets", 3, 1),
                                             ("quintuplets", 5, 1), ("sextuplets", 6, 1), ("septuplets", 7, 1), ("nonuplets", 9, 1),
                                             ("quarter-quintuplets", 5, 4)]
        for (id, grid, span) in tuplets { add(BeatRhythm(id: id, grid: grid, onsets: Array(0..<grid), span: span, group: .tuplets)) }

        // One beat of sixteenths: every combination (15, minus the ones equal to simpler values).
        add(BeatRhythm(id: "eighth", grid: 2, onsets: [1], group: .sixteenths))
        for s in subsets(4) { add(BeatRhythm(id: "16:" + s.map(String.init).joined(), grid: 4, onsets: s, group: .sixteenths)) }

        // Triplet eighths: every combination.
        for s in subsets(3) { add(BeatRhythm(id: "3:" + s.map(String.init).joined(), grid: 3, onsets: s, group: .triplets)) }

        // Sextuplets (triplet sixteenths) that start on the beat.
        for s in subsets(6) where s.first == 0 {
            add(BeatRhythm(id: "6:" + s.map(String.init).joined(), grid: 6, onsets: s, group: .sextuplets))
        }

        // Thirty-seconds: sixteenths with some of them split in two (metal and drum fills).
        for odd in subsets(4) {
            let s = [0, 2, 4, 6] + odd.map { $0 * 2 + 1 }
            add(BeatRhythm(id: "32:" + s.sorted().map(String.init).joined(separator: "."), grid: 8, onsets: s, group: .thirtySeconds))
        }

        // Two beats of eighths and sixteenths: syncopations (8-4-8, dotted quarter + 8, …).
        for s in subsets(4) where s.first == 0 {
            add(BeatRhythm(id: "s8:" + s.map(String.init).joined(), grid: 4, onsets: s, span: 2, group: .syncopation))
        }
        let twoBeatSixteenths: [(String, [Int])] = [("habanera", [0, 3, 4, 6]), ("3-3-2", [0, 3, 6]), ("cinquillo", [0, 2, 3, 5, 6]),
                                                    ("16-8-8.-16", [0, 1, 3, 6]), ("8.-8.-8", [0, 3, 6]), ("16-8.-8.-16", [0, 1, 4, 7]),
                                                    ("baiao", [0, 3, 6]), ("8-16-16-8-16-16", [0, 2, 3, 4, 6, 7]),
                                                    ("16-16-8-16-16-8", [0, 1, 2, 4, 5, 6]), ("16-8-16-16-8-16", [0, 1, 3, 4, 5, 7])]
        for (id, s) in twoBeatSixteenths { add(BeatRhythm(id: id, grid: 8, onsets: s, span: 2, group: .syncopation)) }

        // Quarter-note and half-note triplet figures.
        for sub in subsets(3) where sub.count < 3 {
            add(BeatRhythm(id: "q3:" + sub.map(String.init).joined(), grid: 3, onsets: sub, span: 2, group: .tuplets))
        }
        // Funk sixteenth syncopations over two beats.
        let funk: [(String, [Int])] = [("funk1", [0, 3, 5]), ("funk2", [0, 2, 3, 6]), ("funk3", [0, 3, 5, 6]), ("funk4", [0, 1, 3, 6]),
                                       ("funk5", [0, 3, 4, 7]), ("funk6", [0, 2, 5, 7]), ("funk7", [0, 3, 6, 7]), ("funk8", [0, 1, 4, 6]),
                                       ("funk9", [0, 2, 3, 5, 6]), ("funk10", [0, 3, 4, 5, 7]), ("funk11", [1, 3, 5, 7]), ("funk12", [0, 5])]
        for (id, s) in funk { add(BeatRhythm(id: id, grid: 8, onsets: s, span: 2, group: .syncopation)) }

        // Whole-bar grooves in sixteenths (4 beats).
        let bar: [(String, [Int])] = [("son-3-2", [0, 3, 6, 10, 12]), ("son-2-3", [2, 4, 8, 11, 14]), ("rumba-3-2", [0, 3, 7, 10, 12]),
                                      ("rumba-2-3", [2, 4, 8, 11, 15]), ("bossa", [0, 3, 6, 10, 13]), ("tresillo", [0, 6, 12]),
                                      ("3-3-2-bar", [0, 6, 12]), ("3-3-3-3-4", [0, 3, 6, 9, 12]), ("3-3-3-3-2-2", [0, 3, 6, 9, 12, 14]),
                                      ("2-3-3-3-3-2", [0, 2, 5, 8, 11, 14]), ("bembe", [0, 4, 8, 10, 14]), ("shiko", [0, 4, 6, 10, 12]),
                                      ("soukous", [0, 3, 6, 10, 11]), ("gahu", [0, 3, 6, 10, 14]), ("backbeat", [4, 12]),
                                      ("four-on-floor-offbeats", [2, 6, 10, 14]), ("charleston", [0, 6]), ("reggaeton", [0, 3, 4, 6, 8, 11, 12, 14])]
        for (id, s) in bar { add(BeatRhythm(id: id, grid: 16, onsets: s, span: 4, group: .latin)) }

        // Polyrhythms and displaced pulses: N even clicks over M beats.
        let poly: [(String, Int, Int)] = [("2:3", 2, 3), ("4:3", 4, 3), ("3:4", 3, 4), ("5:4", 5, 4), ("5:2", 5, 2), ("7:4", 7, 4),
                                          ("3:2", 3, 2), ("5:3", 5, 3), ("7:2", 7, 2), ("2:5", 2, 5)]
        for (id, n, m) in poly { add(BeatRhythm(id: "poly" + id, grid: n, onsets: Array(0..<n), span: m, group: .polyrhythm)) }
        // Dotted values across beats: dotted eighths (3 sixteenths), dotted quarters, groups of 5 sixteenths.
        add(BeatRhythm(id: "dotted8-chain", grid: 12, onsets: [0, 3, 6, 9], span: 3, group: .polyrhythm))
        add(BeatRhythm(id: "dotted4-chain", grid: 6, onsets: [0, 3], span: 3, group: .polyrhythm))
        add(BeatRhythm(id: "5-sixteenths", grid: 20, onsets: [0, 5, 10, 15], span: 5, group: .polyrhythm))
        add(BeatRhythm(id: "7-sixteenths", grid: 28, onsets: [0, 7, 14, 21], span: 7, group: .polyrhythm))
        return list
    }

    /// Words for VoiceOver: «пауза, шестнадцатая, восьмая с точкой» instead of «п16-8.».
    public static func spokenName(_ r: BeatRhythm) -> String {
        let named = name(r)
        guard named == r.shortName else { return named }
        let words: [String: String] = ["1": "целая", "2": "половинная", "4": "четверть", "8": "восьмая", "16": "шестнадцатая", "32": "тридцать вторая"]
        func say(_ token: Substring) -> String {
            var t = String(token)
            var rest = ""
            if t.hasPrefix("п") { t.removeFirst(); rest = t.isEmpty ? "пауза" : "пауза " }
            let dotted = t.hasSuffix(".")
            if dotted { t.removeLast() }
            let tied = t.split(separator: "+").map { words[String($0)] ?? String($0) }.joined(separator: " лигой ")
            return rest + tied + (dotted ? " с точкой" : "")
        }
        return r.shortName.split(separator: "-").map(say).joined(separator: ", ")
    }

    /// Name for VoiceOver and the picker.
    public static func name(_ r: BeatRhythm) -> String {
        let names: [String: String] = [
            "whole": "Целые", "half": "Половинные", "quarter": "Четверти", "eighths": "Восьмые", "sixteenths": "Шестнадцатые",
            "thirtyseconds": "Тридцать вторые", "half-triplets": "Триоль половинными", "quarter-triplets": "Триоль четвертями",
            "triplets": "Триоли", "quintuplets": "Квинтоли", "sextuplets": "Секстоли", "septuplets": "Септоли", "nonuplets": "Ноноли",
            "quarter-quintuplets": "Квинтоль четвертями", "eighth": "Восьмая на слабую", "habanera": "Хабанера", "cinquillo": "Синкильо",
            "baiao": "Байон", "son-3-2": "Клаве сон 3-2", "son-2-3": "Клаве сон 2-3", "rumba-3-2": "Клаве румба 3-2",
            "rumba-2-3": "Клаве румба 2-3", "bossa": "Босса-нова", "tresillo": "Тресильо", "3-3-2-bar": "3-3-2 восьмыми",
            "3-3-3-3-4": "3-3-3-3-4 шестнадцатыми", "3-3-3-3-2-2": "3-3-3-3-2-2", "2-3-3-3-3-2": "2-3-3-3-3-2", "bembe": "Бембе",
            "shiko": "Шико", "soukous": "Сукус", "gahu": "Гаху", "backbeat": "Бэкбит 2 и 4", "four-on-floor-offbeats": "Слабые восьмые",
            "charleston": "Чарльстон", "reggaeton": "Реггетон", "dotted8-chain": "Восьмые с точкой (4 на 3)",
            "dotted4-chain": "Четверти с точкой", "5-sixteenths": "Группы по 5 шестнадцатых", "7-sixteenths": "Группы по 7 шестнадцатых",
        ]
        if let n = names[r.id] { return n }
        if r.id.hasPrefix("poly") { return "Полиритм " + r.id.dropFirst(4) }
        return r.shortName
    }
}
