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

// MARK: - Chords of a progression (FB-11)

/// A chord written as a Roman numeral relative to the key: degree 1…7 of the major scale, an accidental
/// («♭VII», «♯iv°») and a chord type («ii7» → m7, «V7» → 7, «iiø7» → m7♭5). Minor-key progressions use the
/// usual flats relative to the major scale: «i ♭VI ♭III ♭VII».
public struct ProgressionChord: Hashable, Sendable, Codable {
    public var degree: Int
    public var accidental: Int
    public var chordId: String
    /// Bars this chord lasts (FB-24: 1, 2 or 4; the playback setting may override it).
    public var bars: Int

    public init(degree: Int, accidental: Int = 0, chordId: String, bars: Int = 1) {
        precondition((1...7).contains(degree), "Degrees are 1…7")
        self.degree = degree
        self.accidental = accidental
        self.chordId = chordId
        self.bars = bars
    }

    /// Any chord in a key: the degree by the root's letter, the accidental from the major scale (in C: E♭ → ♭III).
    public init(root: NoteName, in key: NoteName, chordId: String, bars: Int = 1) {
        let degree = key.letter.steps(to: root.letter) + 1
        var accidental = mod(root.pitchClass - key.pitchClass - DegreeLabel.majorSemitones(degree), 12)
        if accidental > 6 { accidental -= 12 }
        self.init(degree: degree, accidental: accidental, chordId: chordId, bars: bars)
    }

    /// Parses «I», «ii7», «V7», «Imaj7», «♭VII», «bVI», «iiø7», «vii°», «vii°7», «i(maj7)», «IVsus4», «I5».
    public init?(numeral text: String, bars: Int = 1) {
        var rest = Substring(text.trimmedSpaces)
        var accidental = 0
        while let ch = rest.first, "♭b♯#".contains(ch) {
            accidental += "♭b".contains(ch) ? -1 : 1
            rest = rest.dropFirst()
        }
        let romanLetters = rest.prefix { "IViv".contains($0) }
        guard !romanLetters.isEmpty else { return nil }
        let numerals = ["I": 1, "II": 2, "III": 3, "IV": 4, "V": 5, "VI": 6, "VII": 7]
        guard let degree = numerals[romanLetters.uppercased()] else { return nil }
        let upper = romanLetters.first!.isUppercase
        guard romanLetters.allSatisfy({ $0.isUppercase == upper }) else { return nil }
        let suffix = String(rest.dropFirst(romanLetters.count))
        guard let id = ProgressionChord.chordId(suffix: suffix, major: upper) else { return nil }
        self.init(degree: degree, accidental: accidental, chordId: id, bars: bars)
    }

    private static func chordId(suffix: String, major: Bool) -> String? {
        let table: [String: String] = major
            ? ["": "maj", "7": "7", "maj7": "maj7", "Δ7": "maj7", "Δ": "maj7", "+": "aug", "aug": "aug", "6": "6",
               "9": "9", "maj9": "maj9", "sus4": "sus4", "sus2": "sus2", "7sus4": "7sus4", "5": "5", "add9": "add9",
               "13": "13", "11": "11", "7♭9": "7b9", "7b9": "7b9", "7♯9": "7#9", "7#9": "7#9"]
            : ["": "m", "7": "m7", "ø7": "m7b5", "ø": "m7b5", "°": "dim", "o": "dim", "°7": "dim7", "o7": "dim7",
               "(maj7)": "mmaj7", "maj7": "mmaj7", "6": "m6", "9": "m9", "11": "m11", "add9": "madd9"]
        guard let id = table[suffix], ChordLibrary.anyChord(id: id) != nil else { return nil }
        return id
    }

    public var chord: Chord { ChordLibrary.anyChord(id: chordId) ?? ChordLibrary.major }

    /// The root in `key`, spelled by the degree's letter (E: ♭VI → C, not B♯).
    public func root(in key: NoteName) -> NoteName {
        NoteName.spelling(letter: key.letter.advanced(by: degree - 1),
                          pitchClass: key.pitchClass + DegreeLabel.majorSemitones(degree) + accidental)
    }

    /// «ii7», «♭VII», «iiø7» — how the chord is written in the ribbon.
    public var numeral: String {
        let romans = ["I", "II", "III", "IV", "V", "VI", "VII"]
        let minorFamily: Set<String> = ["m", "m7", "m7b5", "dim", "dim7", "mmaj7", "m6", "m9", "m11", "madd9", "m13"]
        let base = romans[degree - 1]
        let roman = minorFamily.contains(chordId) ? base.lowercased() : base
        let prefix = accidental == 0 ? "" : String(repeating: accidental < 0 ? "♭" : "♯", count: abs(accidental))
        let suffix: String
        switch chordId {
        case "maj", "m": suffix = ""
        case "m7", "7": suffix = "7"
        case "m7b5": suffix = "ø7"
        case "dim": suffix = "°"
        case "dim7": suffix = "°7"
        case "mmaj7": suffix = "(maj7)"
        case "aug": suffix = "+"
        case "m6": suffix = "6"
        case "m9": suffix = "9"
        case "m11": suffix = "11"
        case "madd9": suffix = "add9"
        default: suffix = chord.symbol
        }
        return prefix + roman + suffix
    }
}

/// A progression in a key. Chords are relative (Roman numerals), so transposing (TH-7) only moves the key.
public struct Progression: Hashable, Sendable, Codable, Identifiable {
    public var id: String
    public var name: String
    public var key: NoteName
    public var chords: [ProgressionChord]

    public init(id: String, name: String, key: NoteName, chords: [ProgressionChord]) {
        self.id = id
        self.name = name
        self.key = key
        self.chords = chords
    }

    /// From a numeral string: «ii7 V7 Imaj7». Nil if any numeral does not parse.
    public init?(id: String, name: String, key: NoteName, numerals: String) {
        let parsed = numerals.split(separator: " ").map { ProgressionChord(numeral: String($0)) }
        guard !parsed.isEmpty, parsed.allSatisfy({ $0 != nil }) else { return nil }
        self.init(id: id, name: name, key: key, chords: parsed.compactMap { $0 })
    }

    /// Roots and chord types in the current key.
    public var symbols: [Transposition.ChordSymbol] {
        chords.map { Transposition.ChordSymbol(root: $0.root(in: key), chord: $0.chord) }
    }

    /// TH-7: the same progression in another key.
    public func transposed(to newKey: NoteName) -> Progression {
        var p = self
        p.key = newKey
        return p
    }

    /// TH-7: by semitones, choosing the simpler spelling of the new key (no double accidentals, fewest
    /// accidentals in the key's major scale).
    public func transposed(bySemitones semitones: Int) -> Progression {
        let pc = mod(key.pitchClass + semitones, 12)
        let candidates = NoteName.simpleSpellings(ofPitchClass: pc)
        let best = candidates.min { keyAccidentals($0) < keyAccidentals($1) } ?? key
        return transposed(to: best)
    }

    private func keyAccidentals(_ tonic: NoteName) -> Int {
        (1...7).reduce(0) { sum, degree in
            let n = NoteName.spelling(letter: tonic.letter.advanced(by: degree - 1),
                                      pitchClass: tonic.pitchClass + DegreeLabel.majorSemitones(degree))
            return sum + abs(n.accidental) * (abs(n.accidental) > 1 ? 10 : 1)
        }
    }

    public var totalBars: Int { chords.reduce(0) { $0 + $1.bars } }
}

/// Built-in progressions (FB-11): the common pop, jazz, blues, minor and metal cadences.
public enum ProgressionLibrary {
    private static func make(_ id: String, _ name: String, _ numerals: String, key: NoteName) -> Progression {
        Progression(id: id, name: name, key: key, numerals: numerals)!
    }

    public static func all(key: NoteName) -> [Progression] {
        [
            make("pop", "Поп · I–V–vi–IV", "I V vi IV", key: key),
            make("fifties", "50-е · I–vi–IV–V", "I vi IV V", key: key),
            make("sad-pop", "vi–IV–I–V", "vi IV I V", key: key),
            make("three", "I–IV–V", "I IV V I", key: key),
            make("jazz-251", "Джаз · ii–V–I", "ii7 V7 Imaj7 Imaj7", key: key),
            make("jazz-1625", "Джаз · I–vi–ii–V", "Imaj7 vi7 ii7 V7", key: key),
            make("minor-251", "Минорная ii–V–i", "iiø7 V7 i(maj7) i", key: key),
            make("blues", "Блюз 12 тактов", "I7 I7 I7 I7 IV7 IV7 I7 I7 V7 IV7 I7 V7", key: key),
            make("andalusian", "Андалузская каденция", "i ♭VII ♭VI V", key: key),
            make("epic-minor", "Минор · i–♭VI–♭III–♭VII", "i ♭VI ♭III ♭VII", key: key),
            make("aeolian", "Минор · i–♭VI–♭VII–i", "i ♭VI ♭VII i", key: key),
            make("phrygian", "Фригийский · i–♭II", "i ♭II i ♭II", key: key),
            make("power", "Пауэр-аккорды · I5–♭VI5–♭VII5", "I5 ♭VI5 ♭VII5 I5", key: key),
        ]
    }
}

// MARK: - Voice leading (FB-11, FB-22)

/// A chord of a voiced progression: the chosen voicing, or nil when the chord does not fit the instrument at
/// all; `outOfWindow` — the nearest voicing outside the hand window («вне позиции», FB-22).
public struct VoicedChord: Hashable, Sendable {
    public var root: NoteName
    public var chord: Chord
    public var voicing: ChordVoicing?
    public var outOfWindow: Bool
}

public enum ProgressionVoicer {
    /// FB-22: the 4–5 fret window around the chosen place — one fret below it, three above.
    public static func window(around fret: Int, fretCount: Int) -> ClosedRange<Int> {
        let low = max(1, fret - 1)
        return low...min(fretCount, max(low, fret + 3))
    }

    /// Chooses one voicing per chord so the whole progression is comfortable and the hand moves little:
    /// a Viterbi pass over each chord's most comfortable voicings with the cost
    /// Σ comfort + movement (hand shift, fingers moving on shared strings, strings switching on/off),
    /// rewarding common tones held on the same string and fret.
    /// - Parameters:
    ///   - window: frets the hand stays in (FB-22); open strings count as inside when the window starts at fret 4
    ///     or lower. Chords that do not fit take the nearest voicing outside, marked `outOfWindow`.
    ///   - anchor: the first chord's lowest note (FB-22 «первый аккорд — от выбранной ноты»).
    ///   - loop: the move from the last chord back to the first counts too (playback around).
    public static func voice(_ symbols: [Transposition.ChordSymbol], on fretboard: Fretboard,
                             window: ClosedRange<Int>? = nil, anchor: (course: Int, fret: Int)? = nil,
                             loop: Bool = false, candidates: Int = 24) -> [VoicedChord] {
        guard !symbols.isEmpty else { return [] }
        var options: [[(voicing: ChordVoicing, outside: Bool)]] = []
        for (i, s) in symbols.enumerated() {
            var all: [ChordVoicing] = []
            if i == 0, let anchor {
                all = ChordVoicings.voicings(chord: s.chord, root: s.root, on: fretboard, anchor: anchor, limit: candidates)
            }
            if all.isEmpty {
                all = ChordVoicings.voicings(chord: s.chord, root: s.root, on: fretboard, limit: 80)
            }
            options.append(pick(all, window: window, limit: candidates))
        }

        // Viterbi over the candidates; chords with no voicing are skipped in the chain.
        let present = options.indices.filter { !options[$0].isEmpty }
        guard !present.isEmpty else {
            return symbols.map { VoicedChord(root: $0.root, chord: $0.chord, voicing: nil, outOfWindow: false) }
        }
        var chosen: [Int: Int] = [:]
        // With `loop`, try each first-chord candidate as the fixed start and close the circle.
        let firstChoices = loop ? Array(options[present[0]].indices) : [-1]
        var bestTotal = Double.infinity
        for fixedFirst in firstChoices {
            var cost: [[Double]] = []
            var back: [[Int]] = []
            for (step, index) in present.enumerated() {
                let opts = options[index]
                var row = [Double](repeating: .infinity, count: opts.count)
                var from = [Int](repeating: -1, count: opts.count)
                for (j, o) in opts.enumerated() {
                    let own = o.voicing.cost + (o.outside ? 3 : 0)
                    if step == 0 {
                        if fixedFirst >= 0 && j != fixedFirst { continue }
                        row[j] = own
                    } else {
                        let prev = options[present[step - 1]]
                        for (k, p) in prev.enumerated() where cost[step - 1][k] < .infinity {
                            let c = cost[step - 1][k] + own + movement(p.voicing, o.voicing)
                            if c < row[j] { row[j] = c; from[j] = k }
                        }
                    }
                }
                cost.append(row)
                back.append(from)
            }
            var lastRow = cost[cost.count - 1]
            if loop, fixedFirst >= 0, present.count > 1 {
                let first = options[present[0]][fixedFirst].voicing
                for j in lastRow.indices where lastRow[j] < .infinity {
                    lastRow[j] += movement(options[present[present.count - 1]][j].voicing, first)
                }
            }
            guard let end = lastRow.indices.min(by: { lastRow[$0] < lastRow[$1] }), lastRow[end] < bestTotal else { continue }
            bestTotal = lastRow[end]
            var path = [Int](repeating: 0, count: present.count)
            path[present.count - 1] = end
            for step in stride(from: present.count - 1, to: 0, by: -1) { path[step - 1] = back[step][path[step]] }
            chosen = Dictionary(uniqueKeysWithValues: zip(present, path))
        }
        return symbols.enumerated().map { i, s in
            guard let j = chosen[i] else { return VoicedChord(root: s.root, chord: s.chord, voicing: nil, outOfWindow: false) }
            let o = options[i][j]
            return VoicedChord(root: s.root, chord: s.chord, voicing: o.voicing, outOfWindow: o.outside)
        }
    }

    /// In-window voicings, or — when none fit — the ones nearest to the window, marked outside.
    private static func pick(_ all: [ChordVoicing], window: ClosedRange<Int>?, limit: Int)
        -> [(voicing: ChordVoicing, outside: Bool)] {
        guard let window else { return all.prefix(limit).map { ($0, false) } }
        let inside = all.filter { distance($0, to: window) == 0 }
        if !inside.isEmpty { return inside.prefix(limit).map { ($0, false) } }
        guard let nearest = all.map({ distance($0, to: window) }).min() else { return [] }
        return all.filter { distance($0, to: window) == nearest }.prefix(limit).map { ($0, true) }
    }

    /// Frets outside the window (0 = inside). Open strings are inside when the window starts at fret 4 or lower.
    static func distance(_ v: ChordVoicing, to window: ClosedRange<Int>) -> Int {
        var d = 0
        for n in v.notes {
            if n.fret == 0 {
                if window.lowerBound > 4 { d += window.lowerBound }
                continue
            }
            if n.fret < window.lowerBound { d += window.lowerBound - n.fret }
            if n.fret > window.upperBound { d += n.fret - window.upperBound }
        }
        return d
    }

    /// Hand shift between the centres of the fretted notes, fingers moving on shared strings, strings that
    /// start or stop sounding; −0.4 for each note held on the same string and fret (common tones).
    static func movement(_ a: ChordVoicing, _ b: ChordVoicing) -> Double {
        func centre(_ v: ChordVoicing) -> Double? {
            let fretted = v.notes.filter { $0.fret > 0 }.map { Double($0.fret) }
            return fretted.isEmpty ? nil : fretted.reduce(0, +) / Double(fretted.count)
        }
        var cost = 0.0
        if let ca = centre(a), let cb = centre(b) { cost += abs(ca - cb) * 0.9 }
        let n = min(a.frets.count, b.frets.count)
        for c in 0..<n {
            switch (a.frets[c], b.frets[c]) {
            case let (fa?, fb?):
                if fa == fb { cost -= 0.4 } else if fa > 0 && fb > 0 { cost += Double(abs(fa - fb)) * 0.15 }
            case (nil, nil): break
            default: cost += 0.3
            }
        }
        return cost
    }
}

// MARK: - Playback (FB-24)

/// Strum rhythms of the «Ритм» sheet.
public enum StrumRhythm: String, CaseIterable, Sendable, Codable {
    /// One downstroke on the strong beat of each bar.
    case perBar
    /// A downstroke on every beat.
    case perBeat
    /// Down on the beat, up on the «and».
    case downUpEighths
}

/// One stroke of a chord: when (seconds from the start), which chord, its notes in stroke order with offsets.
public struct StrumEvent: Hashable, Sendable {
    public var time: Double
    public var chordIndex: Int
    public var isDown: Bool
    /// Notes in the order they sound: low → high for a downstroke, high → low for an upstroke.
    public var notes: [FretNote]
    /// Offset of each note from `time` (12 ms per string, FB-23).
    public var offsets: [Double]
    /// How long the notes ring: until the next stroke.
    public var duration: Double
    public var velocity: Double
}

public struct ProgressionTimeline: Sendable {
    public var events: [StrumEvent]
    /// Start of each chord (seconds from the start, after the count-in).
    public var chordStarts: [Double]
    /// Count-in length; the first chord sounds here.
    public var countIn: Double
    /// One pass through the progression (count-in excluded); with looping the pattern repeats with this period.
    public var cycle: Double

    /// Chord sounding at `time` (seconds from the start); nil during the count-in. Wraps when looping.
    public func chordIndex(at time: Double, looping: Bool) -> Int? {
        guard time >= countIn, cycle > 0, !chordStarts.isEmpty else { return nil }
        var t = time - countIn
        if looping { t = t.truncatingRemainder(dividingBy: cycle) } else if t >= cycle { return nil }
        return chordStarts.lastIndex { $0 - countIn <= t + 1e-9 }
    }
}

public enum ProgressionSchedule {
    /// FB-23: 12 ms between strings.
    public static let strumStep = 0.012

    /// The strokes of one pass. `barsPerChord` overrides each chord's own bars when set (FB-24: 1, 2, 4).
    /// Upstrokes take only the top strings (at most four) and play softer, like a real strum.
    public static func build(_ voiced: [VoicedChord], chordBars: [Int], barsPerChord: Int? = nil, beatsPerBar: Int,
                             bpm: Double, rhythm: StrumRhythm, countInBars: Int = 1) -> ProgressionTimeline {
        let beat = 60 / bpm
        let bar = beat * Double(beatsPerBar)
        let countIn = Double(countInBars) * bar
        var events: [StrumEvent] = []
        var starts: [Double] = []
        var t = countIn
        for (i, v) in voiced.enumerated() {
            starts.append(t)
            let bars = barsPerChord ?? max(1, chordBars[safeIndex: i] ?? 1)
            let length = Double(bars) * bar
            var strokes: [(Double, Bool)] = []
            switch rhythm {
            case .perBar:
                for b in 0..<bars { strokes.append((t + Double(b) * bar, true)) }
            case .perBeat:
                for k in 0..<(bars * beatsPerBar) { strokes.append((t + Double(k) * beat, true)) }
            case .downUpEighths:
                for k in 0..<(bars * beatsPerBar * 2) { strokes.append((t + Double(k) * beat / 2, k % 2 == 0)) }
            }
            if let voicing = v.voicing {
                let sorted = voicing.notes.sorted { $0.course < $1.course }
                for (k, stroke) in strokes.enumerated() {
                    let next = k + 1 < strokes.count ? strokes[k + 1].0 : t + length
                    let notes = stroke.1 ? sorted : Array(sorted.suffix(4).reversed())
                    events.append(StrumEvent(time: stroke.0, chordIndex: i, isDown: stroke.1, notes: notes,
                                             offsets: notes.indices.map { Double($0) * strumStep },
                                             duration: next - stroke.0, velocity: stroke.1 ? 0.8 : 0.55))
                }
            }
            t += length
        }
        return ProgressionTimeline(events: events, chordStarts: starts, countIn: countIn, cycle: t - countIn)
    }
}

private extension Array {
    subscript(safeIndex index: Int) -> Element? { indices.contains(index) ? self[index] : nil }
}
