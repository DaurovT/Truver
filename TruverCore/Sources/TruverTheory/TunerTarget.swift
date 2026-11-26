/// Target selection of the tuner (TU-6). Pure logic over one stable pitch estimate; attack detection,
/// windows, octave checks and string holding (TU-2…TU-5, TU-4a) belong to the audio layer.
public enum TunerMode: Hashable, Sendable {
    case auto
    case manual(course: Int, string: Int)
    case chromatic
}

public struct StringRef: Hashable, Sendable {
    public var course: Int
    public var string: Int

    public init(course: Int, string: Int = 0) {
        self.course = course
        self.string = string
    }
}

public enum TunerTarget: Hashable, Sendable {
    /// A string of the tuning. `deviationCents` = played − target (negative: flat, tighten).
    case string(StringRef, target: Pitch, deviationCents: Double)
    /// Nearest note of the temperament; `hint` is the nearest string within ±300 cents, if any.
    case chromatic(nearest: Pitch, deviationCents: Double, hint: Hint?)

    public struct Hint: Hashable, Sendable {
        public var string: StringRef
        public var target: Pitch
        /// played − target, e.g. +200 when an E2 is played against the D2 string of Drop D.
        public var deviationCents: Double
    }

    public var deviationCents: Double {
        switch self {
        case .string(_, _, let d): return d
        case .chromatic(_, let d, _): return d
        }
    }
}

public enum TunerTargeting {
    public static let autoCaptureCents: Double = 150
    public static let hintCents: Double = 300

    public static func resolve(_ pitch: Pitch, tuning: Tuning, mode: TunerMode) -> TunerTarget {
        switch mode {
        case .manual(let course, let string):
            let target = tuning.openPitch(course: course, string: string)
            return .string(StringRef(course: course, string: string), target: target,
                           deviationCents: pitch.cents - target.cents)
        case .chromatic:
            return chromatic(pitch, tuning: tuning, withHint: false)
        case .auto:
            guard let nearest = nearestString(to: pitch, in: tuning) else {
                return chromatic(pitch, tuning: tuning, withHint: false)
            }
            if abs(nearest.deviation) <= autoCaptureCents {
                return .string(nearest.ref, target: nearest.target, deviationCents: nearest.deviation)
            }
            return chromatic(pitch, tuning: tuning, withHint: true)
        }
    }

    static func nearestString(to pitch: Pitch, in tuning: Tuning) -> (ref: StringRef, target: Pitch, deviation: Double)? {
        var best: (StringRef, Pitch, Double)?
        for course in tuning.openCents.indices {
            for string in tuning.openCents[course].indices {
                let target = tuning.openPitch(course: course, string: string)
                let deviation = pitch.cents - target.cents
                if best == nil || abs(deviation) < abs(best!.2) {
                    best = (StringRef(course: course, string: string), target, deviation)
                }
            }
        }
        return best.map { (ref: $0.0, target: $0.1, deviation: $0.2) }
    }

    static func chromatic(_ pitch: Pitch, tuning: Tuning, withHint: Bool) -> TunerTarget {
        let nearest: Pitch
        switch tuning.temperament {
        case .equal:
            nearest = Pitch(midi: Double(pitch.nearestMIDI))
        case .custom(let offsets):
            // Nearest step of a 12-note temperament given as offsets from C (TH-10, P2).
            let candidates = (-1...1).map { shift -> Pitch in
                let midi = pitch.nearestMIDI + shift
                return Pitch(midi: Double(midi)).transposed(byCents: offsets[mod(midi, 12)])
            }
            nearest = candidates.min { abs($0.cents - pitch.cents) < abs($1.cents - pitch.cents) }!
        }
        var hint: TunerTarget.Hint?
        if withHint, let s = nearestString(to: pitch, in: tuning), abs(s.deviation) <= hintCents {
            hint = TunerTarget.Hint(string: s.ref, target: s.target, deviationCents: s.deviation)
        }
        return .chromatic(nearest: nearest, deviationCents: pitch.cents - nearest.cents, hint: hint)
    }
}
