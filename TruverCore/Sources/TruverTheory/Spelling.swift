/// User / instrument preference for black keys.
public enum AccidentalPreference: String, CaseIterable, Sendable, Codable {
    case sharp, flat, auto
}

public enum Direction: Sendable {
    case ascending, descending
}

/// Spelling of scales by the rules of PRD 5.2.1.
public enum ScaleSpeller {
    /// Note names of `scale` built on `tonic`, in degree order. The tonic keeps the given spelling.
    public static func spell(_ scale: Scale, tonic: NoteName, direction: Direction = .ascending) -> [NoteName] {
        switch scale.spellingRule {
        case .degreeLabels:
            // Rules 1, 2, 4, 7: the label number fixes the letter; the accidental follows from the pitch.
            // Double sharps and flats appear where the letter demands them (rule 7).
            return scale.degrees.map { degree in
                NoteName.spelling(letter: tonic.letter.advanced(by: degree.label.letterSteps),
                                  pitchClass: tonic.pitchClass + degree.semitones)
            }
        case .accidentalPreference:
            // Rule 3: flats from a flat tonic; sharps from a sharp or natural tonic; naturals where possible.
            let preferFlats = tonic.accidental < 0
            return scale.degrees.enumerated().map { index, degree in
                index == 0 ? tonic
                    : NoteName.simpleSpelling(ofPitchClass: tonic.pitchClass + degree.semitones, preferFlats: preferFlats)
            }
        case .chromatic:
            // Rule 5: sharps going up, flats going down.
            let preferFlats = direction == .descending
            return scale.degrees.enumerated().map { index, degree in
                index == 0 ? tonic
                    : NoteName.simpleSpelling(ofPitchClass: tonic.pitchClass + degree.semitones, preferFlats: preferFlats)
            }
        }
    }

    /// Sum of accidentals in a spelling; double sharps and flats count as two (rule 6).
    public static func accidentalCount(_ names: [NoteName]) -> Int {
        names.reduce(0) { $0 + abs($1.accidental) }
    }

    /// Picks the enharmonic spelling of the tonic (rule 6): both variants are spelled and the one with
    /// fewer real accidentals wins (A♭ major: 4 against 8 for G♯ major). Ties go to `preference`;
    /// with `.auto` a natural tonic wins, then the sharp one.
    public static func preferredTonic(pitchClass: Int,
                                      scale: Scale,
                                      preference: AccidentalPreference = .auto) -> NoteName {
        let candidates = NoteName.simpleSpellings(ofPitchClass: pitchClass)
        let scored = candidates.map { ($0, accidentalCount(spell(scale, tonic: $0))) }
        let best = scored.map(\.1).min()!
        let tied = scored.filter { $0.1 == best }.map(\.0)
        if tied.count == 1 { return tied[0] }
        switch preference {
        case .sharp: return tied.first { $0.accidental > 0 } ?? tied[0]
        case .flat: return tied.first { $0.accidental < 0 } ?? tied[0]
        case .auto: return tied.first { $0.accidental == 0 } ?? tied.first { $0.accidental > 0 } ?? tied[0]
        }
    }

    /// Spells `scale` from a pitch class using the preferred tonic.
    public static func spell(_ scale: Scale,
                             tonicPitchClass: Int,
                             preference: AccidentalPreference = .auto) -> (tonic: NoteName, notes: [NoteName]) {
        let tonic = preferredTonic(pitchClass: tonicPitchClass, scale: scale, preference: preference)
        return (tonic, spell(scale, tonic: tonic))
    }
}
