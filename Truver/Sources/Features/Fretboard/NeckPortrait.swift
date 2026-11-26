import SwiftUI
import TruverTheory

/// The vertical neck of the canvas («Гриф — позиция», 346 × 396): ivory binding, dark wood with grain and side
/// shading, chrome frets spaced like a real neck, pearl inlays, wound and plain strings with shadows, 32 pt notes.
/// Strings run top to bottom, low string on the left (mirrored for left-handers); frets grow downwards.
struct NeckPortrait: View {
    let courses: Int
    /// First and last fret shown (cells); fret 0 = open strings above the nut.
    let frets: ClosedRange<Int>
    let cells: [NeckCell]
    var leftHanded = false
    /// Courses under the capo are dimmed above it (canvas «капо на 2-м ладу»).
    var capo: Int?
    /// Strings that ring after a chord tap (canvas FB-23): a soft light runs along them.
    var strumming: Set<Int> = []
    /// The same strings in stroke order (low to high): each lights 12 ms after the previous (FB-23, 6.2.5).
    var strumOrder: [Int] = []
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var chordMode = false
    /// FB-20: the path in playing order; `pathCurrent` — the sounding note.
    var path: [FretNote] = []
    /// Note names (or degrees) inside the path notes; the order number is a small badge.
    var pathLabels: [String] = []
    var pathCurrent: Int?
    var playingMode = false
    /// «Аккорд»: strings that do not sound get «×» at the nut, as in the chord diagrams (iPhone UX check).
    var mutedCourses: Set<Int> = []
    /// Landscape draws this neck rotated by ±90°: labels turn back by this angle to stay upright.
    var labelRotation: Double = 0
    /// PR-7: fanned frets — each string has its own scale length, the neutral fret is square to the strings.
    var fan: NeckFan?
    /// The whole neck on one screen: frets spaced closer to even (the 24th was 9 pt), smaller notes.
    var overview = false
    /// Note sizes of the canvas (2026-11-25): «Гамма» 26 / 13 / 10, «Аккорд» and «Поиск» 34, «Прогрессия» 30 / 28,
    /// all notes after a tap 12 with the picked note 38.
    var sizing: NoteSizing = .large
    /// The open strings are drawn by the screen in a fixed row above a scrolling neck: no open band here.
    var openBand = true
    let onTap: (Int, Int) -> Void
    /// Course, fret and the note's centre in the «fretScreen» coordinate space (for the note menu).
    let onLongPress: (Int, Int, CGPoint) -> Void
    /// Canvas S8Loupe: hold and drag — the cell under the finger (and its centre in «fretScreen»), nil on release.
    /// When set, it replaces the long-press menu.
    var onScrub: ((NeckSpot, CGPoint)?) -> Void = { _ in }
    var scrubs = false
    /// Coach mark «Нажмите на ноту» (Features/Tour): this note reports its frame.
    var coachCell: NeckSpot?

    static let stringWidths: [CGFloat] = [4.4, 4.0, 3.6, 3.1, 2.7, 2.3, 1.9, 1.6, 1.25, 1.0]

    var body: some View {
        GeometryReader { proxy in
            let g = Geometry(size: proxy.size, courses: courses, frets: frets, leftHanded: leftHanded, fan: fan, overview: overview, band: openBand)
            ZStack(alignment: .topLeading) {
                board(g)
                if path.isEmpty {
                    ForEach(cells) { cell in
                        if frets.contains(cell.fret) || (cell.fret == 0 && frets.lowerBound <= 1 && openBand) {
                            note(cell, g)
                        }
                    }
                } else {
                    // All scale notes as small dots, the path on top (canvas «Гриф — путь»).
                    ForEach(cells) { cell in
                        if frets.contains(cell.fret) || (cell.fret == 0 && frets.lowerBound <= 1) {
                            Circle().fill(Color(hex: 0x3a3c41)).overlay(Circle().strokeBorder(Color.white.opacity(0.18), lineWidth: 1))
                                .frame(width: 10, height: 10)
                                .position(x: g.x(course: cell.course), y: g.y(fret: cell.fret, course: cell.course))
                                .allowsHitTesting(false)
                        }
                    }
                    pathLines(g).allowsHitTesting(false)
                    ForEach(Array(path.enumerated()), id: \.offset) { index, n in pathNote(index, n, g) }
                }
                ForEach(Array(mutedCourses).sorted(), id: \.self) { course in
                    Text("×").font(Typo.fixed(16, .medium)).foregroundStyle(Theme.textSecondary)
                        .rotationEffect(.degrees(labelRotation))
                        .position(x: g.x(course: course), y: frets.lowerBound <= 1 ? g.y(fret: 0, course: course) : 12)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
                if !strumming.isEmpty { ForEach(Array(strumOrder.enumerated()), id: \.element) { index, course in
                    StrumGlow(delay: Double(index) * 0.012).frame(width: 6, height: proxy.size.height)
                        .opacity(reduceMotion || !strumming.contains(course) ? 0 : 1)
                        .position(x: g.x(course: course), y: proxy.size.height / 2)
                        .allowsHitTesting(false)
                } }
            }
            .contentShape(Rectangle())
            .gesture(SpatialTapGesture().onEnded { value in
                if let hit = g.cell(at: value.location) { onTap(hit.course, hit.fret) }
            })
            .simultaneousGesture(LongPressGesture(minimumDuration: 0.5).sequenced(before: DragGesture(minimumDistance: 0))
                .onChanged { value in
                    guard scrubs, case .second(true, let drag?) = value, let hit = g.cell(at: drag.location) else { return }
                    let origin = proxy.frame(in: .named("fretScreen")).origin
                    onScrub((NeckSpot(course: hit.course, fret: hit.fret),
                             CGPoint(x: origin.x + g.x(course: hit.course), y: origin.y + g.y(fret: hit.fret, course: hit.course))))
                }
                .onEnded { value in
                    if scrubs { onScrub(nil); return }
                    if case .second(true, let drag?) = value, let hit = g.cell(at: drag.location) {
                        let origin = proxy.frame(in: .named("fretScreen")).origin
                        onLongPress(hit.course, hit.fret, CGPoint(x: origin.x + g.x(course: hit.course), y: origin.y + g.y(fret: hit.fret, course: hit.course)))
                    }
                })
        }
    }

    // MARK: Geometry

    struct Geometry {
        let size: CGSize
        let courses: Int
        let frets: ClosedRange<Int>
        let leftHanded: Bool
        var fan: NeckFan? = nil
        var overview = false
        var band = true
        /// Open-string band above the nut when fret 0 is shown (canvas: 30 pt).
        var openBand: CGFloat { band && frets.lowerBound <= 1 ? 30 : 0 }
        var inner: CGFloat { size.width - 8 }
        var margin: CGFloat { 26 }

        /// Centre of a string, in the outer box (binding 4 pt on each side).
        func x(course: Int) -> CGFloat {
            let spacing = courses > 1 ? (inner - 2 * margin) / CGFloat(courses - 1) : 0
            let index = leftHanded ? courses - 1 - course : course
            return 4 + margin + CGFloat(index) * spacing
        }

        /// Distance of fret wire n from the nut on a unit scale (12-TET).
        private func d(_ n: Int) -> CGFloat {
            let real = 1 - pow(2, -Double(n) / 12)
            guard overview else { return NeckPortrait.unit(n) }
            // Overview: 65 % even spacing + 35 % real — high frets stay readable, the neck still looks like a neck.
            let top = Double(max(1, frets.upperBound))
            let even = Double(n) / top * (1 - pow(2, -top / 12))
            return CGFloat(0.65 * even + 0.35 * real)
        }

        private var firstWire: Int { max(0, frets.lowerBound - 1) }

        /// Scale ratio at a fractional string index (0 = lowest); 1 without fanned frets.
        private func ratio(at t: CGFloat) -> CGFloat {
            guard let fan, let first = fan.ratios.first, let last = fan.ratios.last, courses > 1 else { return 1 }
            return CGFloat(first) + CGFloat(last - first) * t / CGFloat(courses - 1)
        }

        /// Along-neck position of wire n on a unit scale for a string with this ratio: the neutral fret stays put.
        private func u(_ n: Int, ratio r: CGFloat) -> CGFloat {
            guard let fan else { return d(n) }
            let dn = d(fan.neutralFret)
            return r * (d(n) - dn) + dn
        }

        private var ratioRange: (CGFloat, CGFloat) {
            let a = ratio(at: 0), b = ratio(at: CGFloat(max(0, courses - 1)))
            return (min(a, b), max(a, b))
        }

        private var unitTop: CGFloat { let (a, b) = ratioRange; return min(u(firstWire, ratio: a), u(firstWire, ratio: b)) }
        private var unitBottom: CGFloat { let (a, b) = ratioRange; return max(u(frets.upperBound, ratio: a), u(frets.upperBound, ratio: b)) }

        /// Canvas (2026-11-25): wire lo−1 sits 3 pt above the top, the last wire 2 pt above the bottom.
        private func map(_ unit: CGFloat) -> CGFloat {
            let span = size.height - openBand + 1
            return openBand - 3 + (unit - unitTop) / max(0.0001, unitBottom - unitTop) * span
        }

        /// y of fret wire n (top edge of the 4 pt wire) along the middle of the neck.
        func wire(_ n: Int) -> CGFloat { map(u(n, ratio: 1)) }

        /// y of fret wire n under a string (fanned frets slant).
        func wire(_ n: Int, course: Int) -> CGFloat { map(u(n, ratio: ratio(at: CGFloat(course)))) }

        /// y of fret wire n at a horizontal position of the outer box (for drawing the slanted wire).
        func wire(_ n: Int, atX px: CGFloat) -> CGFloat {
            let spacing = courses > 1 ? (inner - 2 * margin) / CGFloat(courses - 1) : 1
            var t = (px - 4 - margin) / spacing
            if leftHanded { t = CGFloat(courses - 1) - t }
            return map(u(n, ratio: ratio(at: t)))
        }

        /// Slope of wire n across the box (radians; 0 without fanned frets).
        func wireAngle(_ n: Int) -> Double {
            guard fan != nil else { return 0 }
            let l = wire(n, atX: 4), r = wire(n, atX: size.width - 4)
            return atan2(Double(r - l), Double(size.width - 8))
        }

        func y(fret: Int) -> CGFloat { y(fret: fret, course: nil) }

        func y(fret: Int, course: Int?) -> CGFloat {
            func w(_ n: Int) -> CGFloat { course.map { wire(n, course: $0) } ?? wire(n) }
            if fret == 0 { return fan == nil ? openBand / 2 : w(0) - openBand / 2 }
            return (w(fret - 1) + 4 + w(fret)) / 2
        }

        func cell(at p: CGPoint) -> (course: Int, fret: Int)? {
            let course = (0..<courses).min { abs(x(course: $0) - p.x) < abs(x(course: $1) - p.x) } ?? 0
            if openBand > 0 && p.y < wire(0, course: course) + 3 { return (course, 0) }
            for fret in max(1, frets.lowerBound)...frets.upperBound where p.y <= wire(fret, course: course) + 2 { return (course, fret) }
            return nil
        }
    }

    // MARK: Board (canvas 2026-11-25: steel neck)

    /// Unit distance of wire n from the nut: 12-TET up to the 12th fret, then even steps of the 12th fret's width
    /// (the real 13th–24th frets get 10 pt narrow on a phone — notes would overlap).
    static func unit(_ n: Int) -> CGFloat {
        func real(_ k: Int) -> CGFloat { CGFloat(1 - pow(2, -Double(k) / 12)) }
        guard n > 12 else { return real(n) }
        return real(12) + CGFloat(n - 12) * (real(12) - real(11))
    }

    static let gold = Color(hex: 0xe8b54a)
    static let woundString = Color(hex: 0x9fb0c6)
    static let plainString = Color(hex: 0xb8c5d6)

    private func board(_ g: Geometry) -> some View {
        let w = g.size.width - 8, h = g.size.height
        return ZStack(alignment: .topLeading) {
            // Outer board #3a404a, r 4, shadow 0 30 60 .8 and a 1 pt dark outline.
            RoundedRectangle(cornerRadius: 4)
                .fill(Color(hex: 0x3a404a))
                .shadow(color: .black.opacity(0.8), radius: 30, y: 30)
                .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.black.opacity(0.6), lineWidth: 1).padding(-0.5))
            Canvas { context, _ in
                context.fill(Path(CGRect(x: 0, y: 0, width: w, height: h)), with: .color(Color(hex: 0x2b2f36)))
                let first = max(1, g.frets.lowerBound), last = g.frets.upperBound
                if first <= last {
                    // Inlays: 10 pt #aab3c0 at .4 in the cell centres; double at 12 and 24 (30 % and 70 % across).
                    for fret in first...last where [3, 5, 7, 9, 12, 15, 17, 19, 21, 24].contains(fret) {
                        let xs: [CGFloat] = fret % 12 == 0 ? [(w * 0.3).rounded(), (w * 0.7).rounded()] : [(w * 0.5).rounded()]
                        for x in xs {
                            let y = g.fan == nil ? g.y(fret: fret) : (g.wire(fret - 1, atX: x + 4) + 4 + g.wire(fret, atX: x + 4)) / 2
                            context.fill(Path(ellipseIn: CGRect(x: x - 5, y: y - 5, width: 10, height: 10)), with: .color(Color(hex: 0xaab3c0).opacity(0.4)))
                        }
                    }
                    // Frets: 4 pt, r 2, #6b7380 → #e3e8ef → #6b7380.
                    for fret in first...last {
                        var ctx = context
                        var y = g.wire(fret)
                        if g.fan != nil {
                            y = 0
                            ctx.translateBy(x: 0, y: g.wire(fret, atX: 4))
                            ctx.rotate(by: .radians(g.wireAngle(fret)))
                        }
                        let len = g.fan != nil ? w / CGFloat(cos(g.wireAngle(fret))) : w
                        ctx.fill(Path(roundedRect: CGRect(x: 0, y: y, width: len, height: 4), cornerRadius: 2),
                                 with: .linearGradient(Gradient(stops: [.init(color: Color(hex: 0x6b7380), location: 0), .init(color: Color(hex: 0xe3e8ef), location: 0.5),
                                                                        .init(color: Color(hex: 0x6b7380), location: 1)]),
                                                       startPoint: CGPoint(x: 0, y: y), endPoint: CGPoint(x: 0, y: y + 4)))
                    }
                }
                // Strings: flat, wound #9fb0c6, the two thinnest plain #b8c5d6.
                let widths = Array(Self.stringWidths.suffix(g.courses))
                for course in 0..<g.courses {
                    let x = g.x(course: course) - 4
                    let width = widths[safe: course] ?? 1
                    context.fill(Path(CGRect(x: x - width / 2, y: 0, width: width, height: h)),
                                 with: .color(course >= g.courses - 2 ? Self.plainString : Self.woundString))
                }
            }
            .frame(width: w, height: h)
            .offset(x: 4)
            if g.frets.lowerBound <= 1 {
                // Nut: 10 pt #dfe5ec, shadow 0 4 6 .6.
                Rectangle()
                    .fill(Color(hex: 0xdfe5ec))
                    .frame(width: w, height: 10)
                    .shadow(color: .black.opacity(0.6), radius: 3, y: 4)
                    .rotationEffect(.radians(g.wireAngle(0)), anchor: .topLeading)
                    .offset(x: 4, y: g.fan == nil ? g.openBand : g.wire(0, atX: 4) + 3)
            }
            if let capo, g.frets.contains(capo) {
                // Canvas «капо»: a 10 pt bar r 5 across the board, #e8e2d4 → #a9a296, shadow 0 2 6 .6.
                RoundedRectangle(cornerRadius: 5)
                    .fill(LinearGradient(colors: [Color(hex: 0xe8e2d4), Color(hex: 0xa9a296)], startPoint: .top, endPoint: .bottom))
                    .frame(width: g.size.width, height: 10)
                    .shadow(color: .black.opacity(0.6), radius: 3, y: 2)
                    .rotationEffect(.radians(g.wireAngle(capo)), anchor: .topLeading)
                    .offset(y: g.y(fret: capo) - 10)
                    .allowsHitTesting(false)
            }
        }
        .frame(width: g.size.width, height: g.size.height)
    }

    // MARK: Path

    /// Along a string: a thick line, solid where already played, dashed ahead; to another string: a thin dotted line.
    private func pathLines(_ g: Geometry) -> some View {
        Canvas { context, _ in
            let current = pathCurrent ?? 0
            for (i, pair) in zip(path, path.dropFirst()).enumerated() {
                let a = CGPoint(x: g.x(course: pair.0.course), y: g.y(fret: pair.0.fret, course: pair.0.course))
                let b = CGPoint(x: g.x(course: pair.1.course), y: g.y(fret: pair.1.fret, course: pair.1.course))
                var line = Path(); line.move(to: a); line.addLine(to: b)
                // Canvas «путь»: along a string 7 pt at .92 played, 4 pt dashed 4/6 at .55 ahead;
                // to another string 1.2 pt dotted 1/4 at .75 played, .35 ahead.
                let played = i < current
                if pair.0.course == pair.1.course {
                    context.stroke(line, with: .color(Theme.textPrimary.opacity(played ? 0.92 : 0.55)),
                                   style: StrokeStyle(lineWidth: played ? 7 : 4, lineCap: .round, dash: played ? [] : [4, 6]))
                } else {
                    context.stroke(line, with: .color(Theme.textPrimary.opacity(played ? 0.75 : 0.35)),
                                   style: StrokeStyle(lineWidth: 1.2, lineCap: .round, dash: [1, 4]))
                }
            }
        }
    }

    /// Path note: 26 pt with the note name (or degree), the order number as a badge; the current note — ivory
    /// 40 pt; before playing the start is marked as current (the pressed note was not visible — user feedback).
    private func pathNote(_ index: Int, _ n: FretNote, _ g: Geometry) -> some View {
        let current = pathCurrent ?? 0
        let isCurrent = current == index
        let played = index < current
        let size: CGFloat = overview ? (isCurrent ? 30 : 20) : (isCurrent ? 40 : 26)
        let style: NoteStyle = isCurrent ? NoteStyle(role: .tonic, added: false)
            : (played ? NoteStyle(role: .chordTone, added: false) : NoteStyle(role: .other, added: false))
        let label = pathLabels[safe: index] ?? ""
        return Typo.notes(label.isEmpty ? "\(index + 1)" : label, size: isCurrent ? (overview ? 12 : 14) : (overview ? 8 : (label.count >= 3 ? 8 : 10)), weight: .bold, fixed: true)
            .foregroundStyle(style.text)
            .lineLimit(1).minimumScaleFactor(0.6)
            .padding(.horizontal, 2)
            .frame(width: size, height: size)
            .background(Circle().fill(style.fill))
            .overlay(Circle().strokeBorder(style.border, lineWidth: 1.5))
            .overlay(alignment: .topTrailing) {
                if !label.isEmpty {
                    Text("\(index + 1)").font(Typo.fixed(8, .bold)).foregroundStyle(Theme.background)
                        .padding(.horizontal, 3).frame(minWidth: 13, minHeight: 13)
                        .background(Capsule().fill(Theme.textSecondary))
                        .offset(x: 5, y: -5)
                }
            }
            .background { if isCurrent { Circle().stroke(Color.white.opacity(0.18), lineWidth: 6).frame(width: size + 3, height: size + 3) } }
            .shadow(color: .black.opacity(0.55), radius: 6, y: 5)
            .rotationEffect(.degrees(labelRotation))
            .position(x: g.x(course: n.course), y: g.y(fret: n.fret, course: n.course))
            .animation(Motion.out(Motion.Duration.quick), value: isCurrent)
            .accessibilityHidden(true)
    }

    /// y of a fret's cell centre — for scrolling to the current path note.
    static func cellY(fret: Int, frets: ClosedRange<Int>, courses: Int, size: CGSize, fan: NeckFan? = nil, overview: Bool = false) -> CGFloat {
        Geometry(size: size, courses: courses, frets: frets, leftHanded: false, fan: fan, overview: overview).y(fret: fret)
    }

    // MARK: Notes (canvas 2026-11-25)

    enum NoteSizing { case scale, large, progression, allNotes }

    /// Size, label size and whether the label shows, by the canvas boards.
    private func metrics(_ cell: NeckCell) -> (size: CGFloat, font: CGFloat, label: Bool) {
        if cell.isPlaying { return (40, 14, true) }
        switch sizing {
        case .scale:
            if cell.isMarked || cell.isWrong { return (34, 12, true) }
            switch cell.role {
            case .tonic: return (26, 10, true)
            case .chordTone, .characteristic: return cell.isAdded ? (26, 10, true) : (13, 10, false)
            case .other: return cell.isAdded ? (26, 10, true) : (10, 10, false)
            }
        case .large: return cell.emphasis == .faint ? (30, 12, true) : (34, 12, true)
        case .progression: return cell.role == .tonic ? (30, 12, true) : (28, 12, true)
        case .allNotes: return cell.hasRing ? (38, 12, true) : (12, 10, false)
        }
    }

    private func style(_ cell: NeckCell) -> NoteStyle {
        if cell.isWrong {
            // FB-14 / SM-5: the note was played wrong (red, as the PRD asks).
            return NoteStyle(fill: Theme.danger, border: Color(hex: 0xffb4a8), text: Color(hex: 0x0c0d0f))
        }
        let ivory = NoteStyle(fill: Theme.textPrimary, border: .white, text: Color(hex: 0x0c0d0f))
        let dim = NoteStyle(fill: Color.white.opacity(0.08), border: Color.white.opacity(0.18), text: Color.white.opacity(0.55))
        if cell.isMarked { return ivory }
        switch sizing {
        case .large: return cell.emphasis == .faint ? dim : ivory
        case .allNotes: return cell.hasRing ? ivory : dim
        default: return NoteStyle(role: cell.role, added: cell.isAdded)
        }
    }

    private func note(_ cell: NeckCell, _ g: Geometry) -> some View {
        let style = style(cell)
        let m = metrics(cell)
        let faded = cell.emphasis == .faint && sizing != .large
        // 5.1.4: «соль» → «сол» on dots; three or more characters (solfège) smaller, the dot does not grow.
        let label = cell.label.replacingOccurrences(of: "соль", with: "сол")
        return Typo.notes(m.label ? label : "", size: label.count >= 3 ? m.font - 3 : m.font, weight: .bold, fixed: true)
            .foregroundStyle(style.text)
            .lineLimit(1).minimumScaleFactor(0.6)
            .padding(.horizontal, 2)
            .rotationEffect(.degrees(labelRotation))
            .frame(width: m.size, height: m.size)
            .coachAnchor(coachCell == NeckSpot(course: cell.course, fret: cell.fret) ? CoachCatalog.Anchor.firstTonic : nil)
            .background(Circle().fill(style.fill))
            .overlay(Circle().strokeBorder(style.border, style: StrokeStyle(lineWidth: 1.5, dash: cell.isAdded ? [3, 2.5] : [])))
            .background { if cell.isPlaying { Circle().stroke(Color.white.opacity(0.18), lineWidth: 6).frame(width: m.size + 3, height: m.size + 3) } }
            .background { if cell.hasRing && sizing != .allNotes { Circle().stroke(Color.white.opacity(0.45), lineWidth: 2).frame(width: m.size + 10, height: m.size + 10) } }
            // One shadow for the whole dot: without the group SwiftUI shades the ring onto the fill (8 % darker).
            .compositingGroup()
            .shadow(color: .black.opacity(sizing == .allNotes && !cell.hasRing ? 0 : 0.55), radius: 7, y: 6)
            .opacity(faded ? (chordMode ? 0.28 : 0.55) : 1)
            .position(x: g.x(course: cell.course), y: g.y(fret: cell.fret, course: cell.course))
            .animation(Motion.out(Motion.Duration.quick), value: cell.isPlaying)
            .accessibilityHidden(true)
    }

    struct NoteStyle {
        var fill: Color
        var border: Color
        var text: Color

        init(fill: Color, border: Color, text: Color) {
            self.fill = fill; self.border = border; self.text = text
        }

        init(role: DegreeRole, added: Bool) {
            let dark = Color(red: 24 / 255, green: 26 / 255, blue: 30 / 255, opacity: 0.74)
            let light = Color(hex: 0xeef0f3)
            let ink = Color(hex: 0x0c0d0f)
            if added { fill = dark; border = .white; text = light; return }
            switch role {
            case .tonic: fill = NeckPortrait.gold; border = .white; text = ink
            case .chordTone: fill = Color(red: 143 / 255, green: 196 / 255, blue: 1, opacity: 0.95); border = Color(hex: 0xcfe5ff); text = ink
            case .characteristic: fill = Theme.characteristicNote.opacity(0.95); border = Color(hex: 0xe6dbff); text = ink
            case .other: fill = Color(hex: 0x2b2f36); border = Color(red: 150 / 255, green: 156 / 255, blue: 166 / 255, opacity: 0.7); text = light
            }
        }
    }
}

/// Fine grain along the neck (the canvas uses fractal noise; this is a fixed, seeded set of streaks).
/// PR-7 for drawing: scale ratio of each string to the mean scale (low string first) and the neutral fret.
struct NeckFan: Equatable {
    var ratios: [Double]
    var neutralFret: Int

    init?(_ multiscale: Multiscale?, courses: Int) {
        guard let m = multiscale, m.bassScaleLength != m.trebleScaleLength, courses > 1 else { return nil }
        ratios = m.ratios(courses: courses)
        neutralFret = m.neutralFret
    }
}

struct WoodGrain: View {
    var body: some View {
        Canvas { context, size in
            var seed: UInt64 = 0x9E3779B97F4A7C15
            func next() -> CGFloat {
                seed = seed &* 6364136223846793005 &+ 1442695040888963407
                return CGFloat(seed >> 33) / CGFloat(UInt32.max >> 1)
            }
            for _ in 0..<Int(size.width * 0.9) {
                let x = next() * size.width
                let w = 0.4 + next() * 1.6
                let light = next() > 0.55
                let alpha = 0.03 + next() * 0.1
                let y0 = next() * size.height * 0.3 - size.height * 0.1
                let length = size.height * (0.5 + next())
                let drift = (next() - 0.5) * 6
                var p = Path()
                p.move(to: CGPoint(x: x, y: y0))
                p.addQuadCurve(to: CGPoint(x: x + drift, y: y0 + length), control: CGPoint(x: x - drift, y: y0 + length / 2))
                context.stroke(p, with: .color(light ? Color(red: 0.55, green: 0.42, blue: 0.3, opacity: alpha) : Color.black.opacity(alpha * 1.6)), lineWidth: w)
            }
        }
    }
}

/// Light running along a string after a chord tap (canvas «тап по аккорду», `beatseq` over 2.4 s per string).
struct StrumGlow: View {
    var delay: Double = 0
    @State private var on = false
    @State private var lit = false
    var body: some View {
        RoundedRectangle(cornerRadius: 3)
            .fill(LinearGradient(stops: [.init(color: Theme.textPrimary.opacity(0), location: 0), .init(color: Theme.textPrimary.opacity(0.85), location: 0.2),
                                         .init(color: Theme.textPrimary.opacity(0.85), location: 0.8), .init(color: Theme.textPrimary.opacity(0), location: 1)],
                                 startPoint: .top, endPoint: .bottom))
            .blur(radius: 1.5)
            .opacity(lit && !on ? 1 : 0)
            .onAppear {
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                    lit = true
                    withAnimation(.easeOut(duration: 0.6)) { on = true }
                }
            }
    }
}

// MARK: Scrolling neck (canvas 2026-11-25: «листайте вверх-вниз»)

/// The whole neck in a vertical scroll view, zoomed so that `window` fills the viewport (canvas: «Гамма» 1–12 in
/// 356 pt, «Аккорд» 9 frets in 400 pt): fret numbers scroll with it on the left (right for left-handers), a 4 pt
/// scroll bar counted in frets, fades 26 / 30 pt at the edges of the board.
struct ScrollingNeck: View {
    let courses: Int
    let fretCount: Int
    /// Frets that fill the viewport when it appears or the window changes.
    let window: ClosedRange<Int>
    /// Viewport height (canvas: 356 under the open-string row, 400 without it).
    let height: CGFloat
    /// «Гамма»: the open strings are a fixed row above — the scroll starts at the nut (no open band).
    var openRowOutside = false
    var leftHanded = false
    /// «Лады от капо»: the capo fret is 0, the numbers above count from it (0 = off).
    var capoShift = 0
    /// Visible frets while scrolling («Лады 1–12 из 24»).
    var onVisible: (ClosedRange<Int>) -> Void = { _ in }
    /// Holding a note (the loupe) freezes the scroll.
    var frozen = false
    /// The neck for `frets` (the content is the whole neck).
    let neck: (ClosedRange<Int>) -> NeckPortrait

    static let boardWidth: CGFloat = 310
    @State private var offset: CGFloat = 0

    private var band: CGFloat { openRowOutside ? 0 : 30 }
    private var first: Int { openRowOutside ? 1 : 0 }

    /// Points per unit of `NeckPortrait.unit`.
    private var scale: CGFloat {
        let lo = max(0, window.lowerBound - 1)
        let usable = window.lowerBound == 0 ? height - band + 1 : height + 1
        return usable / max(0.0001, NeckPortrait.unit(window.upperBound) - NeckPortrait.unit(lo))
    }

    private var contentHeight: CGFloat { band - 1 + scale * NeckPortrait.unit(fretCount) }

    private func offset(for lo: Int) -> CGFloat { lo == 0 ? 0 : band + scale * NeckPortrait.unit(lo - 1) }

    /// Continuous fret position of a content y (0 = nut).
    private func fret(at y: CGFloat) -> CGFloat {
        let u = max(0, (y - band) / scale)
        let u12 = NeckPortrait.unit(12), step = u12 - NeckPortrait.unit(11)
        if u <= u12 { return CGFloat(-12 * log2(max(0.0001, 1 - Double(u)))) }
        return 12 + (u - u12) / step
    }

    private func center(_ n: Int) -> CGFloat {
        n == 0 ? band / 2 : band + scale * (NeckPortrait.unit(n - 1) + NeckPortrait.unit(n)) / 2 - 1
    }

    /// Scrolled by our own drag (a ScrollView ignored `scrollTo` on a cold start): the start is exact.
    @State private var dragStart: CGFloat?
    @State private var shownWindow: ClosedRange<Int>?
    private var maxOffset: CGFloat { max(0, contentHeight - height) }

    private func report(_ value: CGFloat) {
        let lo = Int(fret(at: value).rounded()) + 1
        let hi = Int(fret(at: value + height + 1).rounded())
        onVisible(min(lo, fretCount)...max(min(lo, fretCount), min(hi, fretCount)))
    }

    private func jump(to w: ClosedRange<Int>, animated: Bool) {
        let target = min(maxOffset, offset(for: w.lowerBound))
        if animated { withAnimation(Motion.out(Motion.Duration.move)) { offset = target } } else { offset = target }
        shownWindow = w
        report(target)
    }

    var body: some View {
        let boardX: CGFloat = leftHanded ? 18 : 22
        let top = fret(at: offset), bottom = fret(at: offset + height + 1)
        ZStack(alignment: .topLeading) {
            ZStack(alignment: .topLeading) {
                ForEach(max(1, first)...max(1, fretCount), id: \.self) { n in
                    let inlay = [3, 5, 7, 9, 12, 15, 17, 19, 21, 24].contains(n)
                    if n >= capoShift {
                    Text("\(n - capoShift)")
                        .font(Typo.inter(11, n % 12 == 0 || n % 12 == 5 ? .semibold : .regular))
                        .foregroundStyle(inlay ? Theme.textSecondary : Color.white.opacity(0.22))
                        // The canvas mirrors the whole block (scaleX(−1)); the numbers stay right-aligned.
                        .frame(width: 18, alignment: .trailing)
                        .position(x: leftHanded ? 341 : 9, y: center(n))
                    }
                }
                neck(first...fretCount)
                    .frame(width: Self.boardWidth, height: contentHeight)
                    .offset(x: boardX)
            }
            .frame(width: 350, height: contentHeight, alignment: .topLeading)
            .offset(y: -offset)
        }
        .frame(width: 350, height: height, alignment: .topLeading)
        .clipped()
        .contentShape(Rectangle())
        .simultaneousGesture(DragGesture(minimumDistance: 8)
            .onChanged { value in
                guard !frozen else { return }
                let start = dragStart ?? offset
                if dragStart == nil { dragStart = offset }
                offset = min(maxOffset, max(0, start - value.translation.height))
                report(offset)
            }
            .onEnded { value in
                defer { dragStart = nil }
                guard !frozen, let start = dragStart else { return }
                // A flick carries on: the predicted end, eased out.
                let target = min(maxOffset, max(0, start - value.predictedEndTranslation.height))
                withAnimation(Motion.out(Motion.Duration.slow)) { offset = target }
                report(target)
            })
        .onAppear { if shownWindow != window { jump(to: window, animated: false) } }
        .onChange(of: window) { _, w in jump(to: w, animated: true) }
        .onChange(of: height) { _, _ in jump(to: window, animated: false) }
        .overlay(alignment: .topLeading) {
            ZStack(alignment: .topLeading) {
                if offset > 1 || !openRowOutside {
                    LinearGradient(colors: [Color(hex: 0x0d0e10), Color(hex: 0x0d0e10, opacity: 0)], startPoint: .top, endPoint: .bottom)
                        .frame(width: Self.boardWidth, height: 26).offset(x: boardX)
                }
                LinearGradient(colors: [Color(hex: 0x0d0e10, opacity: 0), Color(hex: 0x0d0e10)], startPoint: .top, endPoint: .bottom)
                    .frame(width: Self.boardWidth, height: 30).offset(x: boardX, y: height - 30)
                // Scroll bar: track white .08, thumb ivory .6, counted in frets.
                RoundedRectangle(cornerRadius: 2).fill(Color.white.opacity(0.08)).frame(width: 4, height: height)
                    .offset(x: leftHanded ? 0 : 346)
                RoundedRectangle(cornerRadius: 2).fill(Theme.textPrimary.opacity(0.6))
                    .frame(width: 4, height: max(8, (bottom - top) / CGFloat(max(1, fretCount)) * height))
                    .offset(x: leftHanded ? 0 : 346, y: max(0, top) / CGFloat(max(1, fretCount)) * height)
            }
            .allowsHitTesting(false)
        }
        .frame(width: 350, height: height)
    }
}

// MARK: Landscape whole neck (canvas FixLandScale)

/// The portrait neck turned −90° (nut on the left, low string at the bottom) in a horizontal scroll view: board
/// 746 × 268 at (66, 76) of the 844 × 390 board, frets 1–12 in view; open strings in a column at x 49, fret numbers
/// under the cells at 348 (11 pt), a 34 pt fade at the right edge, a 4 pt scroll bar at 368 counted in frets.
struct LandscapeWholeNeck: View {
    let fretCount: Int
    let courses: Int
    let openCells: [NeckCell]
    var capoShift = 0
    let neck: (ClosedRange<Int>) -> NeckPortrait

    private let length: CGFloat = 746
    private let across: CGFloat = 268
    @State private var offset: CGFloat = 0

    private var scale: CGFloat { (length + 1) / NeckPortrait.unit(min(12, fretCount)) }
    private var content: CGFloat { scale * NeckPortrait.unit(fretCount) - 1 }

    private func center(_ n: Int) -> CGFloat { scale * (NeckPortrait.unit(n - 1) + NeckPortrait.unit(n)) / 2 - 1 }

    private func fret(at x: CGFloat) -> CGFloat {
        let u = max(0, x / scale)
        let u12 = NeckPortrait.unit(12), step = u12 - NeckPortrait.unit(11)
        if u <= u12 { return CGFloat(-12 * log2(max(0.0001, 1 - Double(u)))) }
        return 12 + (u - u12) / step
    }

    var body: some View {
        let g = NeckPortrait.Geometry(size: CGSize(width: across, height: 30), courses: courses, frets: 0...1, leftHanded: false)
        let top = fret(at: offset), bottom = fret(at: offset + length + 1)
        ZStack(alignment: .topLeading) {
            // Open strings: rings on #0d0e10 (tonic 24 gold, chord tones 14 blue, the rest 10 grey).
            ForEach(openCells) { cell in
                let tonic = cell.role == .tonic, chord = cell.role == .chordTone
                let size: CGFloat = tonic ? 24 : (chord ? 14 : 10)
                let color: Color = tonic ? NeckPortrait.gold : (chord ? Color(hex: 0x8fc4ff) : Color(red: 150 / 255, green: 156 / 255, blue: 166 / 255, opacity: 0.8))
                Typo.notes(tonic || chord ? cell.label : "", size: 10, weight: .bold, fixed: true)
                    .foregroundStyle(color).lineLimit(1).minimumScaleFactor(0.5)
                    .frame(width: size, height: size)
                    .background(Circle().fill(Color(hex: 0x0d0e10)))
                    .overlay(Circle().strokeBorder(color, lineWidth: 2))
                    .position(x: 49, y: 76 + across - g.x(course: cell.course))
            }
            Text("0").font(Typo.inter(11, .semibold)).foregroundStyle(Theme.textSecondary)
                .frame(width: 20).position(x: 49, y: 355)
            ScrollView(.horizontal) {
                ZStack(alignment: .topLeading) {
                    neck(1...fretCount)
                        .frame(width: across, height: content)
                        .rotationEffect(.degrees(-90))
                        .frame(width: content, height: across)
                    ForEach(1...max(1, fretCount), id: \.self) { n in
                        let inlay = [3, 5, 7, 9, 12, 15, 17, 19, 21, 24].contains(n)
                        if n >= capoShift {
                        Text("\(n - capoShift)").font(Typo.inter(11))
                            .foregroundStyle(inlay ? Theme.textSecondary : Color.white.opacity(0.25))
                            .frame(width: 20)
                            .position(x: center(n), y: 279)
                        }
                    }
                }
                .frame(width: content, height: across + 30, alignment: .topLeading)
                .background(GeometryReader { proxy in
                    Color.clear.preference(key: LandscapeNeckOffsetKey.self, value: -proxy.frame(in: .named("landNeck")).minX)
                })
            }
            .scrollIndicators(.hidden)
            .coordinateSpace(name: "landNeck")
            .onPreferenceChange(LandscapeNeckOffsetKey.self) { offset = $0 }
            .frame(width: length, height: across + 30)
            .clipped()   // the turned neck draws past the scroll view otherwise
            .offset(x: 66, y: 76)
            LinearGradient(colors: [Color(hex: 0x0d0e10, opacity: 0), Color(hex: 0x0d0e10)], startPoint: .leading, endPoint: .trailing)
                .frame(width: 34, height: across).offset(x: 778, y: 76).allowsHitTesting(false)
            RoundedRectangle(cornerRadius: 2).fill(Color.white.opacity(0.08)).frame(width: length, height: 4).offset(x: 66, y: 368)
            RoundedRectangle(cornerRadius: 2).fill(Theme.textPrimary.opacity(0.6))
                .frame(width: max(8, (bottom - top) / CGFloat(max(1, fretCount)) * length), height: 4)
                .offset(x: 66 + max(0, top) / CGFloat(max(1, fretCount)) * length, y: 368)
        }
        .frame(width: 844, height: 390, alignment: .topLeading)
    }
}

private struct LandscapeNeckOffsetKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}
