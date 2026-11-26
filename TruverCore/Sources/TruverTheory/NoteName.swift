/// One of the seven note letters.
public enum Letter: Int, CaseIterable, Sendable, Codable {
    case c, d, e, f, g, a, b

    public var naturalPitchClass: Int { [0, 2, 4, 5, 7, 9, 11][rawValue] }

    public func advanced(by steps: Int) -> Letter {
        Letter(rawValue: mod(rawValue + steps, 7))!
    }

    /// Number of letter steps from `self` up to `other` (0…6).
    public func steps(to other: Letter) -> Int { mod(other.rawValue - rawValue, 7) }

    public var symbol: String { ["C", "D", "E", "F", "G", "A", "B"][rawValue] }
}

/// A spelled pitch class: letter + accidental (−2 = 𝄫, −1 = ♭, 0 = ♮, +1 = ♯, +2 = 𝄪).
public struct NoteName: Hashable, Sendable, Codable, CustomStringConvertible {
    public var letter: Letter
    public var accidental: Int

    public init(_ letter: Letter, _ accidental: Int = 0) {
        self.letter = letter
        self.accidental = accidental
    }

    public var pitchClass: Int { mod(letter.naturalPitchClass + accidental, 12) }

    /// Spells `pitchClass` with the given letter, choosing the smallest accidental (range −5…+6).
    public static func spelling(letter: Letter, pitchClass: Int) -> NoteName {
        var diff = mod(pitchClass - letter.naturalPitchClass, 12)
        if diff > 6 { diff -= 12 }
        return NoteName(letter, diff)
    }

    /// All spellings of a pitch class with at most one accidental (e.g. 8 → G♯, A♭; 0 → C, B♯).
    public static func simpleSpellings(ofPitchClass pc: Int) -> [NoteName] {
        Letter.allCases
            .map { spelling(letter: $0, pitchClass: pc) }
            .filter { abs($0.accidental) <= 1 }
    }

    /// Spelling of a pitch class with the natural if possible, otherwise ♯ or ♭.
    public static func simpleSpelling(ofPitchClass pc: Int, preferFlats: Bool) -> NoteName {
        let options = simpleSpellings(ofPitchClass: pc)
        if let natural = options.first(where: { $0.accidental == 0 }) { return natural }
        let wanted = preferFlats ? -1 : 1
        return options.first(where: { $0.accidental == wanted }) ?? options[0]
    }

    public func transposed(by interval: Interval) -> NoteName {
        NoteName.spelling(letter: letter.advanced(by: interval.letterSteps),
                          pitchClass: pitchClass + interval.semitones)
    }

    /// Plain ASCII-free description with Unicode accidentals, international notation ("F♯", "B𝄫").
    public var description: String { letter.symbol + Accidental.symbol(accidental) }

    /// Parses "C", "F#", "F♯", "Bb", "B♭", "Cx", "C𝄪", "Ebb", "E𝄫".
    public init?(parsing text: String) {
        guard let (name, rest) = NoteName.parsePrefix(Substring(text)), rest.isEmpty else { return nil }
        self = name
    }

    static func parsePrefix(_ text: Substring) -> (NoteName, Substring)? {
        guard let first = text.first,
              let letter = Letter.allCases.first(where: { $0.symbol == String(first).uppercased() })
        else { return nil }
        var accidental = 0
        var rest = text.dropFirst()
        while let ch = rest.first {
            switch ch {
            case "#", "♯": accidental += 1
            case "x", "𝄪": accidental += 2
            case "b", "♭": accidental -= 1
            case "𝄫": accidental -= 2
            default: return (NoteName(letter, accidental), rest)
            }
            rest = rest.dropFirst()
        }
        return (NoteName(letter, accidental), rest)
    }
}

enum Accidental {
    static func symbol(_ accidental: Int) -> String {
        switch accidental {
        case 0: return ""
        case 1: return "♯"
        case 2: return "𝄪"
        case -1: return "♭"
        case -2: return "𝄫"
        case let a where a > 0: return String(repeating: "𝄪", count: a / 2) + (a % 2 == 1 ? "♯" : "")
        default:
            let a = -accidental
            return String(repeating: "𝄫", count: a / 2) + (a % 2 == 1 ? "♭" : "")
        }
    }
}

/// A spelled note with an octave in scientific pitch notation (A4 = 440 Hz; the octave belongs to the
/// letter, so B♯3 sounds as C4 and C♭4 sounds as B3).
public struct SpelledNote: Hashable, Sendable, Codable, CustomStringConvertible {
    public var name: NoteName
    public var octave: Int

    public init(_ name: NoteName, octave: Int) {
        self.name = name
        self.octave = octave
    }

    /// Spells a MIDI note with the given name. `name.pitchClass` must equal `midi mod 12`.
    public init(_ name: NoteName, midi: Int) {
        precondition(name.pitchClass == mod(midi, 12), "Name \(name) does not match MIDI \(midi)")
        let base = midi - name.letter.naturalPitchClass - name.accidental
        self.init(name, octave: Int((Double(base) / 12).rounded(.down)) - 1)
    }

    public var midi: Int { 12 * (octave + 1) + name.letter.naturalPitchClass + name.accidental }
    public var pitch: Pitch { Pitch(midi: Double(midi)) }

    public var description: String { name.description + String(octave) }

    /// Parses "F♯1", "Bb1", "B0", "C#-1".
    public init?(parsing text: String) {
        guard let (name, rest) = NoteName.parsePrefix(Substring(text)), let octave = Int(rest) else { return nil }
        self.init(name, octave: octave)
    }
}

/// A spelled interval: number of letter steps and number of semitones (major third = 2 steps, 4 semitones).
public struct Interval: Hashable, Sendable, Codable {
    public var letterSteps: Int
    public var semitones: Int

    public init(letterSteps: Int, semitones: Int) {
        self.letterSteps = letterSteps
        self.semitones = semitones
    }

    /// The interval that takes `from` to `to` upward within one octave.
    public init(from: NoteName, to: NoteName) {
        self.init(letterSteps: from.letter.steps(to: to.letter),
                  semitones: mod(to.pitchClass - from.pitchClass, 12))
    }
}
