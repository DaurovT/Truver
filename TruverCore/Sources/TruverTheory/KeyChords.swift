/// A chord built on one degree of a heptatonic scale (TH-4, shown in the chord strip FB-17).
public struct KeyChord: Hashable, Sendable {
    /// Index of the scale degree the chord is built on (0 = tonic).
    public var degreeIndex: Int
    public var root: NoteName
    public var notes: [NoteName]
    /// Library chord, or nil when the stacked thirds give a type outside the library
    /// (possible in exotic scales, e.g. degree II of Hungarian minor).
    public var chord: Chord?
    /// "I", "ii", "♭III", "vii°", "V7", "viiø7".
    public var romanNumeral: String

    public func name(formatter: NoteFormatter = NoteFormatter()) -> String {
        guard let chord else { return formatter.string(root) + "?" }
        return chord.name(root: root, formatter: formatter)
    }
}

public enum KeyChords {
    /// Triads on every degree, stacked in thirds from scale notes. Nil for scales that are not heptatonic.
    public static func triads(_ scale: Scale, tonic: NoteName) -> [KeyChord]? {
        build(scale, tonic: tonic, size: 3)
    }

    /// Seventh chords on every degree. Nil for scales that are not heptatonic.
    public static func sevenths(_ scale: Scale, tonic: NoteName) -> [KeyChord]? {
        build(scale, tonic: tonic, size: 4)
    }

    private static func build(_ scale: Scale, tonic: NoteName, size: Int) -> [KeyChord]? {
        guard scale.count == 7 else { return nil }
        let names = ScaleSpeller.spell(scale, tonic: tonic)
        return (0..<7).map { i in
            let indices = (0..<size).map { (i + 2 * $0) % 7 }
            let base = scale.degrees[i].semitones
            let intervals = indices.map { mod(scale.degrees[$0].semitones - base, 12) }.sorted()
            let chord = ChordLibrary.chord(matching: intervals)
            return KeyChord(degreeIndex: i,
                            root: names[i],
                            notes: indices.map { names[$0] },
                            chord: chord,
                            romanNumeral: roman(degree: scale.degrees[i].label, chord: chord))
        }
    }

    static func roman(degree: DegreeLabel, chord: Chord?) -> String {
        let numerals = ["I", "II", "III", "IV", "V", "VI", "VII"]
        let prefix = Accidental.symbol(degree.accidental)
        let upper = numerals[degree.letterSteps]
        guard let chord else { return prefix + upper }
        let isMinor = chord.intervalSet.contains(3)
        let numeral = isMinor ? upper.lowercased() : upper
        let suffix: String
        switch chord.id {
        case "maj", "m": suffix = ""
        case "dim": suffix = "°"
        case "aug": suffix = "+"
        case "maj7": suffix = "maj7"
        case "7", "m7": suffix = "7"
        case "m7b5": suffix = "ø7"
        case "dim7": suffix = "°7"
        case "mmaj7": suffix = "(maj7)"
        default: suffix = chord.symbol
        }
        return prefix + numeral + suffix
    }
}

/// Transposition of scales and progressions (TH-7).
public enum Transposition {
    public struct ChordSymbol: Hashable, Sendable {
        public var root: NoteName
        public var chord: Chord
        public init(root: NoteName, chord: Chord) {
            self.root = root
            self.chord = chord
        }
    }

    /// Moves every root by the interval from `fromKey` to `toKey`, keeping letter relationships
    /// (C → E♭: D → F, B → D).
    public static func transpose(_ progression: [ChordSymbol], from fromKey: NoteName, to toKey: NoteName) -> [ChordSymbol] {
        let interval = Interval(from: fromKey, to: toKey)
        return progression.map { ChordSymbol(root: $0.root.transposed(by: interval), chord: $0.chord) }
    }

    /// A scale is transposed by spelling it on the new tonic.
    public static func transpose(_ scale: Scale, to tonic: NoteName) -> [NoteName] {
        ScaleSpeller.spell(scale, tonic: tonic)
    }
}
