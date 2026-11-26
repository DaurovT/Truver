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

/// FB-20 «Путь»: the scale as one numbered run over the neck.
public enum PathKind: String, CaseIterable, Sendable, Codable {
    /// 3 notes per string, low string to high: position after position.
    case threePerString
    /// 4 notes per string: each string starts higher on the neck — one diagonal pass across the whole neck.
    case fourDiagonal
    /// Along one string, up the neck (slides).
    case oneString

    public var notesPerString: Int {
        switch self {
        case .threePerString: return 3
        case .fourDiagonal: return 4
        case .oneString: return 0
        }
    }
}

public enum ScalePath {
    /// The path from `start` (a cell holding a scale note) upwards, in playing order.
    /// N-per-string paths go across the strings to the highest one; the one-string path goes up the neck to the last
    /// fret. Notes that would fall off the neck end the path.
    public static func build(_ kind: PathKind, scale: Scale, tonic: NoteName, on fretboard: Fretboard,
                             start: (course: Int, fret: Int)) -> [FretNote] {
        guard var pitch = fretboard.pitch(course: start.course, fret: start.fret) else { return [] }
        let maxFret = fretboard.instrument.fretCount
        func note(_ course: Int, _ fret: Int, _ pitch: Pitch) -> FretNote {
            FretNote(course: course, fret: fret, pitch: pitch, degreeIndex: scale.degreeIndex(of: pitch, tonic: tonic) ?? 0)
        }
        func next(after p: Pitch) -> Pitch {
            let base = Pitch.cents(ofPitchClass: tonic.pitchClass)
            let octave = ((p.cents - base) / 1200).rounded(.down)
            var best = Double.infinity
            for o in [octave, octave + 1] {
                for degree in scale.degrees {
                    let c = base + o * 1200 + degree.cents
                    if c > p.cents + 1, c < best { best = c }
                }
            }
            return Pitch(cents: best)
        }
        var result: [FretNote] = [note(start.course, start.fret, pitch)]
        switch kind {
        case .oneString:
            while true {
                pitch = next(after: pitch)
                guard let fret = fretboard.fret(for: pitch, course: start.course), fret <= maxFret, fret > (result.last?.fret ?? 0) else { break }
                result.append(note(start.course, fret, pitch))
            }
        case .threePerString, .fourDiagonal:
            let perString = kind.notesPerString
            var course = start.course
            var onString = 1
            while true {
                pitch = next(after: pitch)
                if onString >= perString, course + 1 < fretboard.courseCount,
                   let f = fretboard.fret(for: pitch, course: course + 1), f <= maxFret {
                    // Move to the next string — unless the note lies below its open pitch (a wide interval such as
                    // the fifth of a drop tuning): then it stays on this string.
                    course += 1
                    onString = 0
                    result.append(note(course, f, pitch))
                    onString += 1
                    continue
                }
                if onString >= perString && course + 1 >= fretboard.courseCount { break }   // the top string is done
                guard let fret = fretboard.fret(for: pitch, course: course), fret <= maxFret,
                      fret > (result.last.map { $0.course == course ? $0.fret : -1 } ?? -1) else { break }
                result.append(note(course, fret, pitch))
                onString += 1
                if onString > perString + 3 { break }
            }
        }
        return result
    }
}
