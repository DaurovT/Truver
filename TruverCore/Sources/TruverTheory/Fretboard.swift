/// A note on the neck: physical course, fret, pitch and its degree in the shown scale or chord.
public struct FretNote: Hashable, Sendable {
    public var course: Int
    public var fret: Int
    public var pitch: Pitch
    public var degreeIndex: Int

    public init(course: Int, fret: Int, pitch: Pitch, degreeIndex: Int) {
        self.course = course
        self.fret = fret
        self.pitch = pitch
        self.degreeIndex = degreeIndex
    }
}

/// The neck of an instrument in one tuning. A course is drawn as one line (5.1.2), so the
/// fretboard uses the main (first) string of each course.
public struct Fretboard: Sendable {
    public let instrument: Instrument
    public let tuning: Tuning

    public init(instrument: Instrument, tuning: Tuning) {
        precondition(instrument.fits(tuning), "Tuning does not match the instrument's strings")
        self.instrument = instrument
        self.tuning = tuning
    }

    public init?(instrument: Instrument) {
        guard let tuning = instrument.currentTuning else { return nil }
        self.init(instrument: instrument, tuning: tuning)
    }

    public var courseCount: Int { instrument.courses.count }

    /// The fret that acts as the nut: the capo fret, or 0.
    public var openFret: Int { instrument.capo }

    public func pitch(course: Int, fret: Int) -> Pitch? {
        instrument.pitch(course: course, fret: fret, tuning: tuning)
    }

    /// Fret where `pitch` sounds on `course` (±10 cents), nil if it is not on the playable part of that string.
    public func fret(for pitch: Pitch, course: Int) -> Int? {
        let open = tuning.openPitch(course: course).cents
        let range = instrument.playableFrets(course: course)
        switch instrument.frets {
        case .equalTempered:
            let fret = Int(((pitch.cents - open) / 100).rounded())
            guard range.contains(fret), abs(open + Double(fret) * 100 - pitch.cents) <= 10 else { return nil }
            return fret
        case .custom:
            return range.first { fret in
                guard let p = self.pitch(course: course, fret: fret) else { return false }
                return abs(p.cents - pitch.cents) <= 10
            }
        }
    }

    /// Course indices sorted by open pitch (low to high); equals physical order except for re-entrant tunings.
    public var coursesByPitch: [Int] {
        (0..<courseCount).sorted { a, b in
            let pa = tuning.openPitch(course: a).cents, pb = tuning.openPitch(course: b).cents
            return pa == pb ? a < b : pa < pb
        }
    }

    /// All notes of a scale on the whole neck ("весь гриф", FB-6).
    public func notes(of scale: Scale, tonic: NoteName) -> [FretNote] {
        var result: [FretNote] = []
        for course in 0..<courseCount {
            for fret in instrument.playableFrets(course: course) {
                guard let p = pitch(course: course, fret: fret),
                      let degree = scale.degreeIndex(of: p, tonic: tonic) else { continue }
                result.append(FretNote(course: course, fret: fret, pitch: p, degreeIndex: degree))
            }
        }
        return result
    }

    /// Chord tones on the whole neck (FB-17); `degreeIndex` points into `chord.degrees`.
    public func notes(of chord: Chord, root: NoteName) -> [FretNote] {
        let rootCents = Pitch.cents(ofPitchClass: root.pitchClass)
        var result: [FretNote] = []
        for course in 0..<courseCount {
            for fret in instrument.playableFrets(course: course) {
                guard let p = pitch(course: course, fret: fret) else { continue }
                let rel = mod(p.cents - rootCents, 1200)
                if let index = chord.degrees.firstIndex(where: {
                    let d = abs(rel - mod($0.cents, 1200))
                    return min(d, 1200 - d) <= 10
                }) {
                    result.append(FretNote(course: course, fret: fret, pitch: p, degreeIndex: index))
                }
            }
        }
        return result
    }
}
