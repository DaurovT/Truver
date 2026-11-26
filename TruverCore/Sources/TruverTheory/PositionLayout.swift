/// Scale positions on any tuning and number of strings (FB-4, FB-5). Positions are computed,
/// not drawn from templates for standard 6-string tuning.
public enum LayoutKind: String, Sendable, Codable {
    /// Consecutive scale notes, a fixed count per string (FB-4).
    case threeNotesPerString
    /// A 4–5 fret window, 2–3 notes per string (FB-5).
    case boxes
}

/// Notes-per-string pattern for 8-note scales (FB-4), chosen by the user.
public enum EightNotePattern: String, Sendable, Codable {
    case threeThreeTwo
    case fourFour
}

public struct LayoutOptions: Hashable, Sendable {
    /// When false, open strings (and the capo fret) are not used.
    public var allowOpenStrings: Bool
    public var eightNotePattern: EightNotePattern

    public init(allowOpenStrings: Bool = true, eightNotePattern: EightNotePattern = .threeThreeTwo) {
        self.allowOpenStrings = allowOpenStrings
        self.eightNotePattern = eightNotePattern
    }
}

public struct ScalePosition: Identifiable, Hashable, Sendable {
    /// 1-based number, positions are ordered up the neck.
    public var number: Int
    public var kind: LayoutKind
    /// Scale degree the position starts from on the lowest string.
    public var startDegree: Int
    /// Notes in playing order (ascending pitch).
    public var notes: [FretNote]
    /// Fingers 0 (open) … 4, parallel to `notes` (labels "пальцы", FB-2). Heuristic.
    public var fingers: [Int]
    /// Some notes did not fit on the neck or in the window and were left out.
    public var isTruncated: Bool
    /// Hand cost of the layout (lower is easier).
    public var cost: Double

    public var id: Int { number }

    public var fretRange: ClosedRange<Int> {
        let frets = notes.map(\.fret)
        return (frets.min() ?? 0)...(frets.max() ?? 0)
    }
}

public enum PositionLayout {
    /// Notes per string by scale size (FB-4): 7 → 3; 5 → 2; 6 → 2/3 alternating; 8 → 3-3-2 or 4-4.
    public static func notesPerString(scaleSize: Int, options: LayoutOptions = LayoutOptions()) -> [Int] {
        switch scaleSize {
        case 5: return [2]
        case 6: return [2, 3]
        case 8: return options.eightNotePattern == .fourFour ? [4] : [3, 3, 2]
        case ...4: return [2]
        default: return [3]
        }
    }

    /// All positions of `scale` on `fretboard`, one per starting degree, sorted up the neck.
    public static func positions(_ kind: LayoutKind,
                                 scale: Scale,
                                 tonic: NoteName,
                                 on fretboard: Fretboard,
                                 options: LayoutOptions = LayoutOptions()) -> [ScalePosition] {
        guard fretboard.courseCount > 0 else { return [] }
        let context = Context(fretboard: fretboard, scale: scale, tonic: tonic, options: options)
        var found: [ScalePosition] = []
        var seen = Set<[Int]>()
        for degree in scale.degrees.indices {
            let position: ScalePosition?
            switch kind {
            case .threeNotesPerString: position = context.threeNotesPerString(startDegree: degree)
            case .boxes: position = context.box(startDegree: degree)
            }
            guard let position, !position.notes.isEmpty else { continue }
            let key = position.notes.flatMap { [$0.course, $0.fret] }
            if seen.insert(key).inserted { found.append(position) }
        }
        // The same shapes repeat an octave (12 frets) higher: continue up the neck while every note fits in the
        // instrument's frets (22 or 24 — a 7th position ending at fret 15 is not the end of a 24-fret neck).
        let maxFret = fretboard.instrument.fretCount
        var queue = found
        while let base = queue.first {
            queue.removeFirst()
            let shifted = base.notes.map { n in
                FretNote(course: n.course, fret: n.fret + 12, pitch: n.pitch.transposed(byCents: 1200), degreeIndex: n.degreeIndex)
            }
            // The top of the neck: keep a shape whose upper notes run past the last fret, cut at that fret, so the
            // positions end at the last fret (24) — as long as at least half of the shape fits.
            let fitting = shifted.filter { $0.fret <= maxFret && context.isAllowed(fret: $0.fret, course: $0.course) }
            guard !fitting.isEmpty, fitting.count * 2 >= shifted.count, fitting.first?.fret ?? .max <= maxFret else { continue }
            let truncated = fitting.count < shifted.count
            let key = fitting.flatMap { [$0.course, $0.fret] }
            guard seen.insert(key).inserted else { continue }
            let fingers = kind == .boxes ? Fingering.box(fitting, openFret: fretboard.openFret)
                                         : Fingering.perString(fitting, openFret: fretboard.openFret)
            let copy = ScalePosition(number: 0, kind: base.kind, startDegree: base.startDegree, notes: fitting, fingers: fingers,
                                     isTruncated: base.isTruncated || truncated, cost: base.cost)
            found.append(copy)
            if !truncated { queue.append(copy) }
        }
        found.sort { ($0.fretRange.lowerBound, $0.startDegree) < ($1.fretRange.lowerBound, $1.startDegree) }
        for i in found.indices { found[i].number = i + 1 }
        return found
    }

    /// FB-25 «Гамма от ноты»: the position that starts on this cell — it is the lowest note, and the shape goes up
    /// the strings from there. Nil when the cell is not a scale note.
    public static func position(from start: (course: Int, fret: Int), kind: LayoutKind, scale: Scale, tonic: NoteName,
                                on fretboard: Fretboard, options: LayoutOptions = LayoutOptions()) -> ScalePosition? {
        guard let first = fretboard.pitch(course: start.course, fret: start.fret),
              let startDegree = scale.degreeIndex(of: first, tonic: tonic) else { return nil }
        let context = Context(fretboard: fretboard, scale: scale, tonic: tonic, options: options)
        guard let startIndex = context.order.firstIndex(of: start.course) else { return nil }
        let strings = Array(context.order[startIndex...])
        var notes = [context.note(course: start.course, fret: start.fret, pitch: first)]
        var truncated = false
        switch kind {
        case .threeNotesPerString:
            let pattern = notesPerString(scaleSize: scale.count, options: options)
            var pitch = first
            var stringIndex = 0, onString = 1
            walk: while true {
                let target = pattern[stringIndex % pattern.count]
                if onString >= target && stringIndex + 1 >= strings.count { break }
                pitch = context.nextScalePitch(after: pitch)
                if onString >= target, let f = fretboard.fret(for: pitch, course: strings[stringIndex + 1]),
                   context.isAllowed(fret: f, course: strings[stringIndex + 1]) {
                    stringIndex += 1
                    onString = 1
                    notes.append(context.note(course: strings[stringIndex], fret: f, pitch: pitch))
                    continue walk
                }
                // A wide interval (the fifth of a drop tuning): the note stays on this string.
                let course = strings[stringIndex]
                guard let f = fretboard.fret(for: pitch, course: course), context.isAllowed(fret: f, course: course),
                      onString < target + 2 else { truncated = true; break walk }
                notes.append(context.note(course: course, fret: f, pitch: pitch))
                onString += 1
            }
            return ScalePosition(number: 0, kind: kind, startDegree: startDegree, notes: notes,
                                 fingers: Fingering.perString(notes, openFret: fretboard.openFret),
                                 isTruncated: truncated, cost: context.stretchCost(notes))
        case .boxes:
            // A 5-fret window from this note: every scale note above it, string by string, at most 3 per string.
            let window = start.fret...min(fretboard.instrument.fretCount, start.fret + 4)
            var last = first
            for (i, course) in strings.enumerated() {
                var count = i == 0 ? 1 : 0
                for f in window where count < 3 && context.isAllowed(fret: f, course: course) {
                    guard let p = fretboard.pitch(course: course, fret: f), p > last,
                          scale.degreeIndex(of: p, tonic: tonic) != nil else { continue }
                    notes.append(context.note(course: course, fret: f, pitch: p))
                    last = p
                    count += 1
                }
            }
            return ScalePosition(number: 0, kind: kind, startDegree: startDegree, notes: notes,
                                 fingers: Fingering.box(notes, openFret: fretboard.openFret),
                                 isTruncated: false, cost: context.stretchCost(notes))
        }
    }

    // MARK: - Implementation

    struct Context {
        let fretboard: Fretboard
        let scale: Scale
        let tonic: NoteName
        let options: LayoutOptions
        let order: [Int]

        init(fretboard: Fretboard, scale: Scale, tonic: NoteName, options: LayoutOptions) {
            self.fretboard = fretboard
            self.scale = scale
            self.tonic = tonic
            self.options = options
            self.order = fretboard.coursesByPitch
        }

        var instrument: Instrument { fretboard.instrument }

        func isAllowed(fret: Int, course: Int) -> Bool {
            guard instrument.playableFrets(course: course).contains(fret) else { return false }
            return options.allowOpenStrings || fret != fretboard.openFret
        }

        func lowestAllowedFret(course: Int) -> Int {
            let lower = instrument.playableFrets(course: course).lowerBound
            return isAllowed(fret: lower, course: course) ? lower : lower + 1
        }

        /// First fret on the lowest string where the degree sounds, within one octave above the lowest allowed fret.
        func startFret(degree: Int) -> Int? {
            let course = order[0]
            let lower = lowestAllowedFret(course: course)
            return (lower...(lower + 11)).first { fret in
                guard isAllowed(fret: fret, course: course), let p = fretboard.pitch(course: course, fret: fret) else { return false }
                return scale.degreeIndex(of: p, tonic: tonic) == degree
            }
        }

        /// The next scale pitch strictly above `pitch`.
        func nextScalePitch(after pitch: Pitch) -> Pitch {
            let base = Pitch.cents(ofPitchClass: tonic.pitchClass)
            let octave = ((pitch.cents - base) / 1200).rounded(.down)
            var best = Double.infinity
            for o in [octave, octave + 1] {
                for degree in scale.degrees {
                    let candidate = base + o * 1200 + degree.cents
                    if candidate > pitch.cents + 1, candidate < best { best = candidate }
                }
            }
            return Pitch(cents: best)
        }

        func note(course: Int, fret: Int, pitch: Pitch) -> FretNote {
            FretNote(course: course, fret: fret, pitch: pitch, degreeIndex: scale.degreeIndex(of: pitch, tonic: tonic) ?? 0)
        }

        // MARK: Three (or N) notes per string

        func threeNotesPerString(startDegree: Int) -> ScalePosition? {
            guard let f0 = startFret(degree: startDegree),
                  let p0 = fretboard.pitch(course: order[0], fret: f0) else { return nil }
            let pattern = PositionLayout.notesPerString(scaleSize: scale.count, options: options)

            // Shape in raw equal-tempered frets; may fall off the neck before shifting.
            var planned: [(course: Int, pitch: Pitch)] = []
            var current = p0
            for (k, course) in order.enumerated() {
                for i in 0..<pattern[k % pattern.count] {
                    if !(k == 0 && i == 0) { current = nextScalePitch(after: current) }
                    planned.append((course, current))
                }
            }
            func rawFret(_ item: (course: Int, pitch: Pitch)) -> Int {
                Int(((item.pitch.cents - fretboard.tuning.openPitch(course: item.course).cents) / 100).rounded())
            }
            let raw = planned.map(rawFret)
            let lowest = order.map { lowestAllowedFret(course: $0) }.min() ?? 0
            var octaveShift = 0.0
            let hitsForbiddenOpen = !options.allowOpenStrings && raw.contains(fretboard.openFret)
            if raw.contains(where: { $0 < lowest }) || hitsForbiddenOpen {
                if (raw.max() ?? 0) + 12 <= instrument.fretCount { octaveShift = 1200 }
            } else if (raw.max() ?? 0) > instrument.fretCount, (raw.min() ?? 0) - 12 >= lowest {
                octaveShift = -1200
            }

            var notes: [FretNote] = []
            var truncated = false
            for item in planned {
                let pitch = item.pitch.transposed(byCents: octaveShift)
                if let fret = fretboard.fret(for: pitch, course: item.course), isAllowed(fret: fret, course: item.course) {
                    notes.append(note(course: item.course, fret: fret, pitch: pitch))
                } else {
                    truncated = true
                }
            }
            return ScalePosition(number: 0, kind: .threeNotesPerString, startDegree: startDegree, notes: notes,
                                 fingers: Fingering.perString(notes, openFret: fretboard.openFret),
                                 isTruncated: truncated, cost: stretchCost(notes))
        }

        func stretchCost(_ notes: [FretNote]) -> Double {
            Dictionary(grouping: notes, by: \.course).values.reduce(0) { sum, group in
                let frets = group.map(\.fret)
                return sum + Double(max(0, (frets.max()! - frets.min()!) - 3)) * 4
            }
        }

        // MARK: Boxes

        func box(startDegree: Int) -> ScalePosition? {
            guard let f0 = startFret(degree: startDegree) else { return nil }
            var best: (cost: Double, notes: [FretNote], skipped: Int)?
            for (back, width) in [(0, 3), (1, 3), (0, 4), (1, 4)] {
                let lo = f0 - back, hi = lo + width
                guard back == 0 || lo >= lowestAllowedFret(course: order[0]) else { continue }
                guard let result = boxInWindow(lo: lo, hi: hi, f0: f0) else { continue }
                let cost = result.cost + Double(back) * 0.5 + Double(width - 3)
                if best == nil || cost < best!.cost { best = (cost, result.notes, result.skipped) }
            }
            guard let best else { return nil }
            return ScalePosition(number: 0, kind: .boxes, startDegree: startDegree, notes: best.notes,
                                 fingers: Fingering.box(best.notes, openFret: fretboard.openFret),
                                 isTruncated: best.skipped > 0, cost: best.cost)
        }

        /// Dynamic programming over strings: each string takes a run of consecutive scale pitches that it
        /// can play inside the window. Costs: notes per string outside 2–3 (exactly 2 for pentatonics),
        /// stretch on one string over 3 frets, reaching outside the window (one fret down, two up — needed
        /// for the fifth between the two lowest strings of Drop tunings), empty strings, skipped pitches.
        func boxInWindow(lo: Int, hi: Int, f0: Int) -> (cost: Double, notes: [FretNote], skipped: Int)? {
            let first = order[0], top = order[order.count - 1]
            guard let p0 = fretboard.pitch(course: first, fret: f0),
                  let topFret = (lo...hi).reversed().first(where: { isAllowed(fret: $0, course: top) }),
                  let maxPitch = fretboard.pitch(course: top, fret: topFret), maxPitch >= p0 else { return nil }

            var pitches = [p0]
            while true {
                let next = nextScalePitch(after: pitches.last!)
                if next.cents > maxPitch.cents + 1 { break }
                pitches.append(next)
            }
            let m = pitches.count, strings = order.count
            let fretOn: [[Int?]] = order.map { course in
                pitches.map { pitch in
                    guard let fret = fretboard.fret(for: pitch, course: course),
                          ((lo - 1)...(hi + 2)).contains(fret),
                          isAllowed(fret: fret, course: course) else { return nil }
                    return fret
                }
            }

            func blockCost(_ s: Int, _ i: Int, _ j: Int) -> Double? {
                let count = j - i
                if count == 0 { return 8 }
                var frets: [Int] = []
                for k in i..<j {
                    guard let f = fretOn[s][k] else { return nil }
                    frets.append(f)
                }
                var cost = Double(frets.filter { !(lo...hi).contains($0) }.count) * 3
                if scale.count == 5 {
                    cost += Double(abs(count - 2)) * 6
                } else {
                    if count < 2 { cost += Double(2 - count) * 6 }
                    if count > 3 { cost += Double(count - 3) * 6 }
                }
                let span = frets.max()! - frets.min()!
                if span > 3 { cost += Double(span - 3) * 4 }
                return cost
            }

            let inf = Double.infinity
            var dp = Array(repeating: Array(repeating: inf, count: m + 1), count: strings)
            var back = Array(repeating: Array(repeating: (prevEnd: 0, start: 0), count: m + 1), count: strings)
            for j in 1...m {
                if let c = blockCost(0, 0, j) { dp[0][j] = c; back[0][j] = (0, 0) }
            }
            if strings > 1 {
                for s in 1..<strings {
                    for j in 0...m {
                        for start in 0...j {
                            guard let block = blockCost(s, start, j) else { continue }
                            for skipped in 0...2 {
                                let prevEnd = start - skipped
                                guard prevEnd >= 1, dp[s - 1][prevEnd] < inf else { continue }
                                let cost = dp[s - 1][prevEnd] + Double(skipped) * 20 + block
                                if cost < dp[s][j] { dp[s][j] = cost; back[s][j] = (prevEnd, start) }
                            }
                        }
                    }
                }
            }
            guard dp[strings - 1][m] < inf else { return nil }

            var notes: [FretNote] = []
            var skipped = 0
            var j = m
            for s in stride(from: strings - 1, through: 0, by: -1) {
                let (prevEnd, start) = back[s][j]
                for k in stride(from: j - 1, through: start, by: -1) {
                    notes.append(note(course: order[s], fret: fretOn[s][k]!, pitch: pitches[k]))
                }
                skipped += start - prevEnd
                j = prevEnd
            }
            return (dp[strings - 1][m], notes.reversed(), skipped)
        }
    }
}

/// Finger labels (FB-2). Simple heuristics; the hand-cost model of FB-9 will refine them.
enum Fingering {
    /// Box: one finger per fret from the lowest fretted note; stretches go to the little finger.
    static func box(_ notes: [FretNote], openFret: Int) -> [Int] {
        let fretted = notes.filter { $0.fret != openFret }.map(\.fret)
        guard let base = fretted.min() else { return notes.map { _ in 0 } }
        return notes.map { $0.fret == openFret ? 0 : min(4, max(1, 1 + $0.fret - base)) }
    }

    /// N notes per string: the hand moves with each string. First note = 1, last = 4 on stretches.
    static func perString(_ notes: [FretNote], openFret: Int) -> [Int] {
        var result = Array(repeating: 0, count: notes.count)
        let groups = Dictionary(grouping: notes.indices, by: { notes[$0].course })
        for indices in groups.values {
            let fretted = indices.filter { notes[$0].fret != openFret }
            guard let low = fretted.map({ notes[$0].fret }).min(), let high = fretted.map({ notes[$0].fret }).max() else { continue }
            let span = high - low
            for i in fretted {
                let offset = notes[i].fret - low
                if span <= 3 {
                    result[i] = 1 + offset
                } else {
                    result[i] = offset == span ? 4 : 1 + Int((Double(offset) / Double(span) * 3).rounded(.down))
                }
            }
        }
        return result
    }
}
