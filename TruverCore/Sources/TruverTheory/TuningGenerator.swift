/// Interval templates of the tuning generator (PRD 5.1.1).
public enum IntervalTemplate: String, Sendable, Codable {
    /// Fourths, with a major third between strings 3 and 2 counted from the highest string.
    case guitar
    /// Guitar template plus a fourth on top (the major third moves to strings 4 and 3 from the top).
    case guitarExtendedHigh
    /// Fourths only.
    case bass

    /// Semitones between neighbouring strings, from the lowest string up (`stringCount − 1` values).
    public func intervals(stringCount n: Int) -> [Int] {
        guard n >= 2 else { return [] }
        switch self {
        case .bass:
            return Array(repeating: 5, count: n - 1)
        case .guitar:
            var result = Array(repeating: 5, count: n - 1)
            // Interval index k joins strings k and k+1 (from the bottom). Strings 3 and 2 from the top
            // are indices n−3 and n−2, so the third is interval n−3.
            if n >= 3 { result[n - 3] = 4 }
            return result
        case .guitarExtendedHigh:
            return IntervalTemplate.guitar.intervals(stringCount: n - 1) + [5]
        }
    }
}

/// Name of a generated tuning: "Стандарт B", "Drop A" (PRD 5.1.3: named by the lowest standard note;
/// Drop tunings by the dropped note).
public struct TuningName: Hashable, Sendable {
    public enum Kind: Sendable { case standard, drop }
    public var kind: Kind
    public var root: NoteName

    public func text(language: Language = .ru, formatter: NoteFormatter = NoteFormatter()) -> String {
        let note = formatter.string(root)
        switch kind {
        case .standard: return (language == .ru ? "Стандарт " : "Standard ") + note
        case .drop: return "Drop " + note
        }
    }
}

/// Generator (PR-2): instrument type + string count + lowest standard note + Drop.
public enum TuningGenerator {
    public struct Result: Sendable {
        /// Open pitches from the lowest string up.
        public var pitches: [Pitch]
        public var notes: [SpelledNote]
        public var name: TuningName
    }

    /// Nil when the type has no interval template (ukulele, mandolin, folk instruments).
    public static func generate(type: InstrumentType,
                                stringCount: Int,
                                lowestStandard: Pitch,
                                drop: Bool = false,
                                preference: AccidentalPreference = .auto) -> Result? {
        guard let template = type.intervalTemplate, stringCount >= 1 else { return nil }
        var pitches = [lowestStandard]
        for step in template.intervals(stringCount: stringCount) {
            pitches.append(pitches.last!.transposed(bySemitones: step))
        }
        // Spelling is decided on the standard tuning so that "Drop" keeps the family's accidentals.
        let standardNotes = TuningSpeller.spell(pitches, preference: preference)
        let usesFlats = standardNotes.contains { $0.name.accidental < 0 }
        var name = TuningName(kind: .standard, root: standardNotes[0].name)
        if drop {
            pitches[0] = pitches[0].transposed(bySemitones: -2)
            name = TuningName(kind: .drop,
                              root: NoteName.simpleSpelling(ofPitchClass: pitches[0].pitchClass, preferFlats: usesFlats))
        }
        let notes = pitches.map {
            SpelledNote(NoteName.simpleSpelling(ofPitchClass: $0.pitchClass, preferFlats: usesFlats), midi: $0.nearestMIDI)
        }
        return Result(pitches: pitches, notes: notes, name: name)
    }

    /// Builds a `Tuning` for an instrument with single-string courses.
    public static func makeTuning(type: InstrumentType,
                                  stringCount: Int,
                                  lowestStandard: Pitch,
                                  drop: Bool = false,
                                  language: Language = .ru) -> Tuning? {
        guard let result = generate(type: type, stringCount: stringCount, lowestStandard: lowestStandard, drop: drop)
        else { return nil }
        return Tuning(name: result.name.text(language: language), openCents: result.pitches.map { [$0.cents] })
    }
}
