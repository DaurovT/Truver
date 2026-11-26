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

// FB-9 «Аккорд», FB-10 «Поиск», FB-21 «Аккорды от ноты»: the full chord library (TH-3b), playable voicings in any
// tuning (one note per string, ≤ 4 fingers + barre, limited stretch), chord recognition from notes, and scales
// that contain given notes.

extension ChordLibrary {
    private typealias T = LocalizedText

    /// TH-3b: the rest of the library. Optional degrees may be left out of a voicing (5 in sevenths and above,
    /// 9 and 11 in 13ths, 3 in 11ths).
    public static let extended: [Chord] = [
        Chord(id: "5", symbol: "5", names: T(ru: "Квинта (пауэр-аккорд)", en: "Power chord"), category: .triad, labels: "1 5"),
        Chord(id: "sus2", symbol: "sus2", names: T(ru: "С задержанием секунды", en: "Suspended 2nd"), category: .suspended, labels: "1 2 5", optional: "5"),
        Chord(id: "sus4", symbol: "sus4", names: T(ru: "С задержанием кварты", en: "Suspended 4th"), category: .suspended, labels: "1 4 5", optional: "5"),
        Chord(id: "7sus4", symbol: "7sus4", names: T(ru: "Септаккорд с квартой", en: "Seventh sus4"), category: .suspended, labels: "1 4 5 ♭7", optional: "5"),
        Chord(id: "6", symbol: "6", names: T(ru: "Мажорный секстаккорд", en: "Major sixth"), category: .sixth, labels: "1 3 5 6", optional: "5"),
        Chord(id: "m6", symbol: "m6", names: T(ru: "Минорный секстаккорд", en: "Minor sixth"), category: .sixth, labels: "1 ♭3 5 6", optional: "5"),
        Chord(id: "6/9", symbol: "6/9", names: T(ru: "Секста с ноной", en: "Six-nine"), category: .sixth, labels: "1 3 5 6 9", optional: "5"),
        Chord(id: "add9", symbol: "add9", names: T(ru: "С добавленной ноной", en: "Added ninth"), category: .added, labels: "1 3 5 9", optional: "5"),
        Chord(id: "madd9", symbol: "m(add9)", names: T(ru: "Минорный с ноной", en: "Minor added ninth"), category: .added, labels: "1 ♭3 5 9", optional: "5"),
        Chord(id: "9", symbol: "9", names: T(ru: "Доминантнонаккорд", en: "Dominant ninth"), category: .extended, labels: "1 3 5 ♭7 9", optional: "5"),
        Chord(id: "maj9", symbol: "maj9", names: T(ru: "Большой мажорный нонаккорд", en: "Major ninth"), category: .extended, labels: "1 3 5 7 9", optional: "5"),
        Chord(id: "m9", symbol: "m9", names: T(ru: "Минорный нонаккорд", en: "Minor ninth"), category: .extended, labels: "1 ♭3 5 ♭7 9", optional: "5"),
        Chord(id: "11", symbol: "11", names: T(ru: "Ундецимаккорд", en: "Eleventh"), category: .extended, labels: "1 3 5 ♭7 9 11", optional: "3 5 9"),
        Chord(id: "m11", symbol: "m11", names: T(ru: "Минорный ундецимаккорд", en: "Minor eleventh"), category: .extended, labels: "1 ♭3 5 ♭7 9 11", optional: "5 9"),
        Chord(id: "13", symbol: "13", names: T(ru: "Терцдецимаккорд", en: "Thirteenth"), category: .extended, labels: "1 3 5 ♭7 9 11 13", optional: "5 9 11"),
        Chord(id: "m13", symbol: "m13", names: T(ru: "Минорный терцдецимаккорд", en: "Minor thirteenth"), category: .extended, labels: "1 ♭3 5 ♭7 9 11 13", optional: "5 9 11"),
        Chord(id: "maj13", symbol: "maj13", names: T(ru: "Большой мажорный терцдецимаккорд", en: "Major thirteenth"), category: .extended, labels: "1 3 5 7 9 13", optional: "5 9"),
        Chord(id: "7b9", symbol: "7♭9", names: T(ru: "Септаккорд с малой ноной", en: "Seven flat nine"), category: .altered, labels: "1 3 5 ♭7 ♭9", optional: "5"),
        Chord(id: "7#9", symbol: "7♯9", names: T(ru: "Септаккорд с большой ноной (хендрикс)", en: "Seven sharp nine"), category: .altered, labels: "1 3 5 ♭7 ♯9", optional: "5"),
        Chord(id: "7#11", symbol: "7♯11", names: T(ru: "Септаккорд с увеличенной ундецимой", en: "Seven sharp eleven"), category: .altered, labels: "1 3 5 ♭7 ♯11", optional: "5"),
        Chord(id: "7b5", symbol: "7♭5", names: T(ru: "Септаккорд с пониженной квинтой", en: "Seven flat five"), category: .altered, labels: "1 3 ♭5 ♭7"),
        Chord(id: "7#5", symbol: "7♯5", names: T(ru: "Увеличенный септаккорд", en: "Seven sharp five"), category: .altered, labels: "1 3 ♯5 ♭7"),
        Chord(id: "13#11", symbol: "13♯11", names: T(ru: "Терцдецимаккорд с ♯11", en: "Thirteen sharp eleven"), category: .altered, labels: "1 3 5 ♭7 9 ♯11 13", optional: "5 9"),
        Chord(id: "quartal", symbol: "4", names: T(ru: "Квартовый аккорд", en: "Quartal"), category: .quartal, labels: "1 4 ♭7"),
    ]

    /// Everything the «Аккорд» mode offers: P0 triads and sevenths plus the extended set.
    public static var full: [Chord] { all + extended + UserLibrary.shared.chords }

    public static func anyChord(id: String) -> Chord? { full.first { $0.id == id } }
}

// MARK: Voicings

/// One playable shape: a fret or nil (muted) per course, from the bass side.
public struct ChordVoicing: Hashable, Sendable, Identifiable {
    public var frets: [Int?]
    public var notes: [FretNote]
    /// Fretting fingers, a barre counting as one.
    public var fingers: Int
    public var barreFret: Int?
    /// Frets between the lowest and highest fretted note (0 = all on one fret).
    public var span: Int
    public var lowestFret: Int { notes.filter { $0.fret > 0 }.map(\.fret).min() ?? 0 }
    public var usesOpenStrings: Bool { notes.contains { $0.fret == 0 } }
    public var bass: FretNote { notes[0] }
    /// Lower is more comfortable.
    public var cost: Double
    public var id: [Int] { frets.map { $0 ?? -1 } }
    /// A wide stretch (5 frets); shown as «растяжка».
    public var isStretch: Bool { span >= 4 }

    /// Fingering by course: 0 open, 1 the barre (or the lowest fret), then 2, 3, 4 up the frets.
    public var fingerNumbers: [Int: Int] {
        var result: [Int: Int] = [:]
        var next = 1
        if let barreFret {
            for n in notes where n.fret == barreFret { result[n.course] = 1 }
            next = 2
        }
        for n in notes.sorted(by: { $0.fret == $1.fret ? $0.course < $1.course : $0.fret < $1.fret }) where result[n.course] == nil {
            if n.fret == 0 { result[n.course] = 0; continue }
            result[n.course] = min(4, next)
            next += 1
        }
        return result
    }
}

public enum ChordVoicings {
    /// Playable voicings of `root` + `chord` on the fretboard, most comfortable first.
    /// - Parameters:
    ///   - bassPitchClass: the lowest note (root by default; another chord tone gives an inversion).
    ///   - anchor: a cell that must sound as the lowest note (FB-21 «Аккорды от ноты»).
    /// TH-3b: when nothing fits, the degree whose omission makes the chord playable — extensions first
    /// (11, 9, then 13 and 6), the fifth last; never the root, third or seventh. nil when no single omission helps.
    public static func omissionHint(chord: Chord, root: NoteName, on fretboard: Fretboard,
                                    anchor: (course: Int, fret: Int)? = nil, knownEmpty: Bool = false) -> DegreeLabel? {
        guard knownEmpty || voicings(chord: chord, root: root, on: fretboard, anchor: anchor, limit: 1).isEmpty else { return nil }
        let order = [11, 9, 13, 6, 5]
        let candidates = chord.requiredDegrees
            .filter { order.contains($0.number) }
            .sorted { order.firstIndex(of: $0.number)! < order.firstIndex(of: $1.number)! }
        for label in candidates {
            let reduced = chord.omitting([label])
            if !voicings(chord: reduced, root: root, on: fretboard, anchor: anchor, limit: 1).isEmpty { return label }
        }
        return nil
    }

    public static func voicings(chord: Chord, root: NoteName, on fretboard: Fretboard,
                                bassPitchClass: Int? = nil, anchor: (course: Int, fret: Int)? = nil,
                                maxSpan: Int = 4, limit: Int = 40, within: ClosedRange<Int>? = nil) -> [ChordVoicing] {
        let n = fretboard.courseCount
        guard n >= 2 else { return [] }
        let rootPC = root.pitchClass
        let tones: [(pc: Int, label: DegreeLabel)] = chord.degrees.map { (((rootPC + $0.semitones) % 12 + 12) % 12, $0.label) }
        let tonePCs = Set(tones.map(\.pc))
        let required = Set(tones.filter { chord.requiredDegrees.contains($0.label) }.map(\.pc))
        let bassPC = anchor.flatMap { fretboard.pitch(course: $0.course, fret: $0.fret)?.pitchClass } ?? bassPitchClass ?? rootPC
        let maxFret = fretboard.instrument.fretCount
        var found: [[Int]: ChordVoicing] = [:]

        // Windows of `maxSpan` frets; open strings are always allowed.
        // `within`: only hand windows starting in these frets (FB-17: the shape nearest to the position, and fast).
        let windowStarts: [Int] = anchor.map { a in Array(max(1, a.fret - maxSpan + 1)...max(1, a.fret)) }
            ?? Array(1...max(1, maxFret - 2)).filter { within?.contains($0) ?? true }
        for start in windowStarts {
            let window = start...min(maxFret, start + maxSpan - 1)
            // Options per course: muted, open, or a fret in the window whose pitch class is a chord tone.
            var options: [[Int?]] = []
            for c in 0..<n {
                var o: [Int?] = [nil]
                for f in [0] + Array(window) where fretboard.instrument.playableFrets(course: c).contains(f) {
                    if let p = fretboard.pitch(course: c, fret: f), tonePCs.contains(p.pitchClass) { o.append(f) }
                }
                options.append(o)
            }
            // Sounding strings form one contiguous run (no muted string inside), at least as many as required tones.
            let minStrings = max(2, min(required.count, 4))
            for low in 0..<n {
                if let anchor, anchor.course != low { continue }
                guard low + minStrings - 1 < n else { continue }
                for high in (low + minStrings - 1)..<n {
                    var current: [Int?] = Array(repeating: nil, count: n)
                    func dfs(_ c: Int) {
                        if c > high {
                            evaluate(current)
                            return
                        }
                        for option in options[c] {
                            guard let f = option else { continue }
                            if c == low {
                                if let anchor, f != anchor.fret { continue }
                                guard fretboard.pitch(course: c, fret: f)?.pitchClass == bassPC else { continue }
                            }
                            current[c] = f
                            if partialFingers(current, upTo: c) <= 4 { dfs(c + 1) }
                            current[c] = nil
                        }
                    }
                    dfs(low)
                }
            }
        }

        func partialFingers(_ frets: [Int?], upTo c: Int) -> Int {
            fingerCount(frets.prefix(c + 1).map { $0 }).fingers
        }

        func evaluate(_ frets: [Int?]) {
            let sounding = frets.enumerated().compactMap { c, f in f.map { (c, $0) } }
            guard sounding.count >= 2 else { return }
            var notes: [FretNote] = []
            for (c, f) in sounding {
                guard let p = fretboard.pitch(course: c, fret: f) else { return }
                notes.append(FretNote(course: c, fret: f, pitch: p, degreeIndex: tones.firstIndex { $0.pc == p.pitchClass } ?? 0))
            }
            let present = Set(notes.map(\.pitch.pitchClass))
            guard required.isSubset(of: present) else { return }
            let fretted = sounding.map(\.1).filter { $0 > 0 }
            let span = (fretted.max() ?? 0) - (fretted.min() ?? 0)
            guard span < maxSpan + 1 else { return }
            let (fingers, barre) = fingerCount(frets)
            guard fingers <= 4 else { return }
            // Comfort: fewer fingers, smaller span, lower on the neck, fewer muted strings inside the hand, more
            // strings sounding (up to 6), open strings welcome, root doubled is fine.
            let muted = frets.count - sounding.count
            var cost = Double(span) * 1.0 + Double(fingers) * 0.6 + Double(fretted.min() ?? 0) * 0.06
            cost += Double(muted) * 0.25 - Double(min(6, sounding.count)) * 0.35
            if barre != nil { cost += 0.3 }
            if span >= 4 { cost += 2.5 }
            // Open strings ring together with high frets only in odd shapes: the higher, the worse.
            if sounding.contains(where: { $0.1 == 0 }), let top = fretted.max(), top > 4 { cost += 2 + Double(top - 4) * 0.5 }
            // Four fingers without a barre are a stretch for the hand.
            if fingers >= 4 && barre == nil { cost += 0.5 }
            if present.count < tonePCs.count { cost += 0.6 * Double(tonePCs.count - present.count) }
            let voicing = ChordVoicing(frets: frets, notes: notes, fingers: fingers, barreFret: barre, span: span, cost: cost)
            if let old = found[voicing.id], old.cost <= cost { return }
            found[voicing.id] = voicing
        }

        // Drop near-duplicates: the same shape with one more or fewer edge string — keep the cheaper.
        // Ties broken by the lowest fret, then the shape itself: `found` is a dictionary, and without a full order
        // equal-cost voicings came out in a different order on every launch («1 из N» changed between runs).
        let sorted = found.values.sorted { a, b in
            if a.cost != b.cost { return a.cost < b.cost }
            if a.lowestFret != b.lowestFret { return a.lowestFret < b.lowestFret }
            return a.id.lexicographicallyPrecedes(b.id)
        }
        var result: [ChordVoicing] = []
        for v in sorted {
            let fretted = Set(v.notes.map { "\($0.course):\($0.fret)" })
            let dup = result.contains { r in
                let other = Set(r.notes.map { "\($0.course):\($0.fret)" })
                return fretted.isSubset(of: other) && other.count - fretted.count <= 1 && r.lowestFret == v.lowestFret
            }
            if !dup { result.append(v) }
            if result.count >= limit { break }
        }
        return result
    }

    /// Fingers needed: notes on the lowest fretted fret across several strings can be a barre (one finger) if no
    /// string inside it is open or muted below the barre fret; every other fretted note takes a finger.
    static func fingerCount(_ frets: [Int?]) -> (fingers: Int, barre: Int?) {
        let fretted = frets.compactMap { $0 }.filter { $0 > 0 }
        guard let minFret = fretted.min() else { return (0, nil) }
        let onMin = frets.enumerated().filter { $0.element == minFret }.map(\.offset)
        if onMin.count >= 2, let first = onMin.first, let last = onMin.last {
            let inside = frets[first...last]
            let barreOK = inside.allSatisfy { f in f.map { $0 >= minFret } ?? false }
            if barreOK {
                return (1 + fretted.filter { $0 != minFret }.count, minFret)
            }
        }
        return (fretted.count, nil)
    }
}

// MARK: Recognition (FB-10)

public struct ChordMatch: Hashable, Sendable {
    public var root: NoteName
    public var chord: Chord
    /// Slash bass when the lowest note is not the root («C6/A»).
    public var bass: NoteName?
    /// Chord tones that were not played («без G»).
    public var missing: [NoteName]

    public func name(formatter: NoteFormatter = NoteFormatter()) -> String {
        var s = chord.name(root: root, formatter: formatter)
        if let bass { s += "/" + formatter.string(bass) }
        if !missing.isEmpty { s += " без " + missing.map { formatter.string($0) }.joined(separator: ", ") }
        return s
    }
}

public enum ChordRecognizer {
    /// Names for the played pitch classes, best first: exact chords with the root in the bass, then exact
    /// inversions (slash), then chords missing one tone. `bass` is the lowest played pitch class.
    public static func identify(pitchClasses: Set<Int>, bass: Int?, preferFlats: Bool = false, limit: Int = 6) -> [ChordMatch] {
        guard pitchClasses.count >= 2 else { return [] }
        var scored: [(ChordMatch, Double)] = []
        for rootPC in 0..<12 {
            for chord in ChordLibrary.full {
                // The root spelling that keeps the chord free of 𝄪 / 𝄫 (D♭7♯11 rather than C♯7♯11 with F𝄪).
                let root = bestRoot(rootPC, chord: chord, preferFlats: preferFlats)
                let tones = Set(chord.degrees.map { ((rootPC + $0.semitones) % 12 + 12) % 12 })
                guard pitchClasses.isSubset(of: tones) else { continue }
                let required = Set(chord.degrees.filter { chord.requiredDegrees.contains($0.label) }.map { ((rootPC + $0.semitones) % 12 + 12) % 12 })
                let missingTones = tones.subtracting(pitchClasses)
                let missingRequired = required.subtracting(pitchClasses)
                guard missingRequired.count <= 1, pitchClasses.contains(rootPC) || pitchClasses.count >= 3 else { continue }
                let spelled = chord.spell(root: root)
                // The names of pressed notes as a guitarist reads them: C, not B♯; G, not F𝄪.
                let plain: (NoteName) -> NoteName = { n in
                    let awkward = abs(n.accidental) > 1 || (n.accidental == 1 && (n.letter == .b || n.letter == .e))
                        || (n.accidental == -1 && (n.letter == .c || n.letter == .f))
                    return awkward ? NoteName.simpleSpelling(ofPitchClass: n.pitchClass, preferFlats: preferFlats) : n
                }
                let missingNames = spelled.filter { missingRequired.contains($0.pitchClass) }.map(plain)
                // The bass is the note the player pressed: never «/F𝄪» for a G.
                let bassName = bass.flatMap { b in b == rootPC ? nil : spelled.first { $0.pitchClass == b }.map(plain) }
                var score = Double(missingRequired.count) * 10 + Double(missingTones.count - missingRequired.count) * 0.5
                if bassName != nil { score += 3 }
                if !pitchClasses.contains(rootPC) { score += 6 }
                score += Double(chord.degrees.count) * 0.3
                score += Double(spelled.filter { abs($0.accidental) > 1 }.count) * 1.5
                if chord.category == .quartal || chord.id == "5" { score += 2 }
                scored.append((ChordMatch(root: root, chord: chord, bass: bassName, missing: missingNames), score))
            }
        }
        var seen = Set<String>()
        return scored.sorted { $0.1 < $1.1 }.map(\.0).filter { seen.insert($0.name()).inserted }.prefix(limit).map { $0 }
    }

    private static func bestRoot(_ pc: Int, chord: Chord, preferFlats: Bool) -> NoteName {
        let preferred = NoteName.simpleSpelling(ofPitchClass: pc, preferFlats: preferFlats)
        // 𝄪/𝄫 are out; B♯, E♯, C♭, F♭ read badly on a guitar (A♭13/C, not G♯13/B♯).
        func cost(_ root: NoteName) -> Int {
            chord.spell(root: root).reduce(0) { sum, n in
                if abs(n.accidental) > 1 { return sum + 10 }
                let awkward = (n.accidental == 1 && (n.letter == .b || n.letter == .e))
                    || (n.accidental == -1 && (n.letter == .c || n.letter == .f))
                return sum + (awkward ? 3 : abs(n.accidental))
            }
        }
        let options = NoteName.simpleSpellings(ofPitchClass: pc).filter { abs($0.accidental) <= 1 }
        let best = options.min { cost($0) < cost($1) } ?? preferred
        return cost(best) < cost(preferred) ? best : preferred
    }

    /// Nothing matches all the notes: the best chord for the notes without one of them («G7♭9 без G — 3 ноты из 4»).
    public static func nearest(pitchClasses: Set<Int>, bass: Int?, preferFlats: Bool = false) -> (match: ChordMatch, matched: Int)? {
        guard pitchClasses.count >= 3 else { return nil }
        var best: (ChordMatch, Int, Int)?     // match, rank among results, matched notes
        for dropped in pitchClasses.sorted() {
            let rest = pitchClasses.subtracting([dropped])
            guard let first = identify(pitchClasses: rest, bass: bass == dropped ? nil : bass, preferFlats: preferFlats, limit: 1).first else { continue }
            let penalty = first.missing.count + (first.bass == nil ? 0 : 1)
            if best == nil || penalty < best!.1 { best = (first, penalty, rest.count) }
        }
        return best.map { ($0.0, $0.2) }
    }
}

// MARK: Scales containing notes (FB-10 «Гаммы с этими нотами», FB-9 «Подходящие гаммы»)

public struct ScaleMatch: Hashable, Sendable {
    public var tonic: NoteName
    public var scale: Scale
}

public enum ScaleFinder {
    /// Scales (any tonic) that contain every pitch class; the bass as tonic and common scales come first.
    public static func scales(containing pitchClasses: Set<Int>, preferredTonic: Int? = nil, limit: Int = 12) -> [ScaleMatch] {
        guard !pitchClasses.isEmpty else { return [] }
        var result: [(ScaleMatch, Double)] = []
        for tonicPC in 0..<12 {
            for (rank, scale) in ScaleLibrary.all.enumerated() {
                let pcs = Set(scale.degrees.map { ((tonicPC + $0.semitones) % 12 + 12) % 12 })
                guard pitchClasses.isSubset(of: pcs) else { continue }
                let tonic = ScaleSpeller.preferredTonic(pitchClass: tonicPC, scale: scale)
                var score = Double(rank) * 0.05 + Double(pcs.count - pitchClasses.count) * 0.4
                if let preferredTonic, preferredTonic == tonicPC { score -= 3 }
                if !pitchClasses.contains(tonicPC) { score += 2 }
                result.append((ScaleMatch(tonic: tonic, scale: scale), score))
            }
        }
        return result.sorted { $0.1 < $1.1 }.prefix(limit).map(\.0)
    }
}
