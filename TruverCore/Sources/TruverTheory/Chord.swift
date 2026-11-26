public enum ChordCategory: String, CaseIterable, Sendable, Codable {
    case triad
    case seventh
    case suspended
    case sixth
    case extended
    case altered
    case added
    case quartal
    case user
}

/// A chord type: degrees from the root plus which of them may be omitted (TH-3).
public struct Chord: Identifiable, Hashable, Sendable, Codable {
    public var id: String
    /// Symbol written after the root: "", "m", "dim", "maj7", "m7♭5".
    public var symbol: String
    public var names: LocalizedText
    public var category: ChordCategory
    public var degrees: [ScaleDegree]
    public var requiredDegrees: [DegreeLabel]
    public var optionalDegrees: [DegreeLabel]
    public var isUserDefined: Bool

    public init(id: String, symbol: String, names: LocalizedText, category: ChordCategory,
                labels: String, optional: String = "", isUserDefined: Bool = false) {
        let all = DegreeLabel.list(labels)
        let omit = optional.isEmpty ? [] : DegreeLabel.list(optional)
        self.id = id
        self.symbol = symbol
        self.names = names
        self.category = category
        self.degrees = all.map(ScaleDegree.init(label:))
        self.optionalDegrees = omit
        self.requiredDegrees = all.filter { !omit.contains($0) }
        self.isUserDefined = isUserDefined
    }

    /// Pitch classes relative to the root, sorted (used to recognise chords built from scale notes).
    public var intervalSet: [Int] { degrees.map { mod($0.semitones, 12) }.sorted() }

    public func spell(root: NoteName) -> [NoteName] {
        degrees.map { degree in
            NoteName.spelling(letter: root.letter.advanced(by: degree.label.letterSteps),
                              pitchClass: root.pitchClass + degree.semitones)
        }
    }

    /// The same chord without these degrees («C13♯11 без 11»): voicings search only for what is left.
    public func omitting(_ labels: Set<DegreeLabel>) -> Chord {
        var c = self
        c.id = id + "-no" + labels.map(\.description).sorted().joined(separator: ",")
        c.degrees.removeAll { labels.contains($0.label) }
        c.requiredDegrees.removeAll { labels.contains($0) }
        c.optionalDegrees.removeAll { labels.contains($0) }
        return c
    }

    /// "Dm", "Bm7♭5" in the given notation.
    public func name(root: NoteName, formatter: NoteFormatter = NoteFormatter()) -> String {
        formatter.string(root) + symbol
    }
}

/// Built-in chord library. v1 (P0) has triads and seventh chords (TH-3a); the full ~60-chord
/// library is P1 (TH-3b) and is added to `all` by appending.
public enum ChordLibrary {
    private typealias T = LocalizedText

    public static let major = Chord(id: "maj", symbol: "", names: T(ru: "Мажорное трезвучие", en: "Major triad"),
                                    category: .triad, labels: "1 3 5")
    public static let minor = Chord(id: "m", symbol: "m", names: T(ru: "Минорное трезвучие", en: "Minor triad"),
                                    category: .triad, labels: "1 ♭3 5")
    public static let diminished = Chord(id: "dim", symbol: "dim", names: T(ru: "Уменьшённое трезвучие", en: "Diminished triad"),
                                         category: .triad, labels: "1 ♭3 ♭5")
    public static let augmented = Chord(id: "aug", symbol: "aug", names: T(ru: "Увеличенное трезвучие", en: "Augmented triad"),
                                        category: .triad, labels: "1 3 ♯5")
    public static let major7 = Chord(id: "maj7", symbol: "maj7", names: T(ru: "Большой мажорный септаккорд", en: "Major seventh"),
                                     category: .seventh, labels: "1 3 5 7", optional: "5")
    public static let dominant7 = Chord(id: "7", symbol: "7", names: T(ru: "Доминантсептаккорд", en: "Dominant seventh"),
                                        category: .seventh, labels: "1 3 5 ♭7", optional: "5")
    public static let minor7 = Chord(id: "m7", symbol: "m7", names: T(ru: "Малый минорный септаккорд", en: "Minor seventh"),
                                     category: .seventh, labels: "1 ♭3 5 ♭7", optional: "5")
    public static let halfDiminished7 = Chord(id: "m7b5", symbol: "m7♭5", names: T(ru: "Полуменьшённый септаккорд", en: "Half-diminished seventh"),
                                              category: .seventh, labels: "1 ♭3 ♭5 ♭7")
    public static let diminished7 = Chord(id: "dim7", symbol: "dim7", names: T(ru: "Уменьшённый септаккорд", en: "Diminished seventh"),
                                          category: .seventh, labels: "1 ♭3 ♭5 𝄫7")
    public static let minorMajor7 = Chord(id: "mmaj7", symbol: "m(maj7)", names: T(ru: "Минорный с большой септимой", en: "Minor-major seventh"),
                                          category: .seventh, labels: "1 ♭3 5 7", optional: "5")

    public static let triads: [Chord] = [major, minor, diminished, augmented]
    public static let sevenths: [Chord] = [major7, dominant7, minor7, halfDiminished7, diminished7, minorMajor7]
    public static let all: [Chord] = triads + sevenths

    public static func chord(id: String) -> Chord? { all.first { $0.id == id } }

    /// The library chord whose intervals above the root are exactly `intervalSet` (sorted, mod 12).
    public static func chord(matching intervalSet: [Int]) -> Chord? {
        all.first { $0.intervalSet == intervalSet }
    }
}
