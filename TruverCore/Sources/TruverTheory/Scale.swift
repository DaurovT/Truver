/// A degree label relative to the major scale: number (1…13) and accidental ("♭3", "♯4", "𝄫7").
/// The number fixes the letter (number − 1 letter steps from the root); the accidental is relative
/// to the major scale degree with that number.
public struct DegreeLabel: Hashable, Sendable, Codable, CustomStringConvertible {
    public var number: Int
    public var accidental: Int

    public init(_ number: Int, _ accidental: Int = 0) {
        precondition(number >= 1, "Degree numbers start at 1")
        self.number = number
        self.accidental = accidental
    }

    /// Semitones of the major-scale degree with this number (9 = 14, 11 = 17, 13 = 21).
    public static func majorSemitones(_ number: Int) -> Int {
        let major = [0, 2, 4, 5, 7, 9, 11]
        let index = number - 1
        return major[index % 7] + 12 * (index / 7)
    }

    public var semitones: Int { DegreeLabel.majorSemitones(number) + accidental }

    /// Letter steps from the root (0…6).
    public var letterSteps: Int { (number - 1) % 7 }

    public var description: String { Accidental.symbol(accidental) + String(number) }

    /// Parses "3", "b3", "♭3", "#4", "♯4", "bb7", "𝄫7".
    public init?(parsing text: String) {
        var accidental = 0
        var rest = Substring(text)
        while let ch = rest.first, !ch.isNumber {
            switch ch {
            case "#", "♯": accidental += 1
            case "x", "𝄪": accidental += 2
            case "b", "♭": accidental -= 1
            case "𝄫": accidental -= 2
            case "♮": break
            default: return nil
            }
            rest = rest.dropFirst()
        }
        guard let number = Int(rest), number >= 1 else { return nil }
        self.init(number, accidental)
    }

    /// Parses a space-separated list: "1 2 ♭3 4 5 ♭6 7".
    static func list(_ text: String) -> [DegreeLabel] {
        text.split(separator: " ").map { token in
            guard let label = DegreeLabel(parsing: String(token)) else {
                preconditionFailure("Bad degree label \(token)")
            }
            return label
        }
    }
}

/// One scale or chord degree: exact height in cents above the root + its label for spelling.
public struct ScaleDegree: Hashable, Sendable, Codable {
    public var cents: Double
    public var label: DegreeLabel

    public init(cents: Double, label: DegreeLabel) {
        self.cents = cents
        self.label = label
    }

    public init(label: DegreeLabel) {
        self.init(cents: Double(label.semitones) * 100, label: label)
    }

    /// Nearest whole semitone (exact for 12-TET degrees).
    public var semitones: Int { Int((cents / 100).rounded()) }
}

public enum ScaleCategory: String, CaseIterable, Sendable, Codable {
    case majorModes
    case harmonicMinorModes
    case melodicMinorModes
    case pentatonicAndBlues
    case symmetric
    case bebop
    case exotic
    case maqam
    case user
}

/// How note names are chosen for a scale (PRD 5.2.1).
public enum SpellingRule: String, Sendable, Codable {
    /// Letters follow degree labels: rules 1, 2, 4, 7 (heptatonic, pentatonic/blues, 8-note, exotic).
    case degreeLabels
    /// Naturals where possible; flats from a flat tonic, otherwise sharps: rule 3 (whole-tone, augmented).
    case accidentalPreference
    /// Sharps ascending, flats descending: rule 5.
    case chromatic
}

/// Reference to the parent scale for modes (PRD 8: "parentScaleId + modeShift").
public struct ModeReference: Hashable, Sendable, Codable {
    public var parentId: String
    public var shift: Int
}

/// Colour roles on the fretboard (FB-3).
public enum DegreeRole: String, Sendable, Codable {
    case tonic
    case chordTone
    case characteristic
    case other
}

public struct Scale: Identifiable, Hashable, Sendable, Codable {
    public var id: String
    public var names: LocalizedText
    public var category: ScaleCategory
    /// Degrees in ascending order; the first is always the root (0 cents).
    public var degrees: [ScaleDegree]
    public var spellingRule: SpellingRule
    /// Index into `degrees` of the note that gives the mode its colour (FB-3), if any.
    public var characteristicDegree: Int?
    public var mode: ModeReference?
    public var isUserDefined: Bool
    /// Hidden until checked by a musician (TH-9).
    public var needsReview: Bool

    public init(id: String,
                names: LocalizedText,
                category: ScaleCategory,
                degrees: [ScaleDegree],
                spellingRule: SpellingRule = .degreeLabels,
                characteristicDegree: Int? = nil,
                mode: ModeReference? = nil,
                isUserDefined: Bool = false,
                needsReview: Bool = false) {
        precondition(degrees.first?.cents == 0, "A scale starts at its root")
        self.id = id
        self.names = names
        self.category = category
        self.degrees = degrees
        self.spellingRule = spellingRule
        self.characteristicDegree = characteristicDegree
        self.mode = mode
        self.isUserDefined = isUserDefined
        self.needsReview = needsReview
    }

    /// Builds a scale from degree labels: `Scale(id:…, labels: "1 2 ♭3 4 5 ♭6 7")`.
    public init(id: String,
                names: LocalizedText,
                category: ScaleCategory,
                labels: String,
                spellingRule: SpellingRule = .degreeLabels,
                characteristic: String? = nil) {
        let degrees = DegreeLabel.list(labels).map(ScaleDegree.init(label:))
        let index = characteristic.flatMap { c in degrees.firstIndex { $0.label.description == DegreeLabel(parsing: c)?.description } }
        self.init(id: id, names: names, category: category, degrees: degrees,
                  spellingRule: spellingRule, characteristicDegree: index)
    }

    public var count: Int { degrees.count }

    /// A mode: the parent scale rotated to start on degree `shift` (TH-2).
    /// Labels are recomputed against the major scale, so heptatonic modes keep one letter per degree.
    public static func mode(of parent: Scale,
                            shift: Int,
                            id: String,
                            names: LocalizedText,
                            category: ScaleCategory? = nil,
                            characteristic: String? = nil) -> Scale {
        let n = parent.count
        let base = parent.degrees[shift].cents
        let rotated = (0..<n).map { i in mod(parent.degrees[(shift + i) % n].cents - base, 1200) }
        let degrees: [ScaleDegree] = rotated.enumerated().map { i, cents in
            if n == 7 {
                let semis = Int((cents / 100).rounded())
                return ScaleDegree(cents: cents, label: DegreeLabel(i + 1, semis - DegreeLabel.majorSemitones(i + 1)))
            }
            return ScaleDegree(cents: cents, label: parent.degrees[(shift + i) % n].label)
        }
        let index = characteristic.flatMap { c in
            degrees.firstIndex { $0.label.description == DegreeLabel(parsing: c)?.description }
        }
        return Scale(id: id, names: names, category: category ?? parent.category, degrees: degrees,
                     spellingRule: parent.spellingRule, characteristicDegree: index,
                     mode: ModeReference(parentId: parent.id, shift: shift))
    }

    /// Colour role of a degree (FB-3): tonic, chord tone (3, 5, 7), the mode's characteristic note, other.
    public func role(ofDegree index: Int) -> DegreeRole {
        if index == 0 { return .tonic }
        if index == characteristicDegree { return .characteristic }
        // Canvas (wins over FB-3's «3, 5, 7»): 3 and 5 are blue, the seventh stays dark on every fretboard board.
        if [3, 5].contains(degrees[index].label.number) { return .chordTone }
        return .other
    }

    /// Does `pitch` belong to this scale built on `tonic`? Returns the degree index (10-cent tolerance).
    public func degreeIndex(of pitch: Pitch, tonic: NoteName, toleranceCents: Double = 10) -> Int? {
        let rel = mod(pitch.cents - Pitch.cents(ofPitchClass: tonic.pitchClass), 1200)
        return degrees.firstIndex { degree in
            let d = abs(rel - degree.cents)
            return min(d, 1200 - d) <= toleranceCents
        }
    }
}
