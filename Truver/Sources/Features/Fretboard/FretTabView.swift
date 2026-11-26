import SwiftUI
import TruverTheory

// «Таб» — the path as a tablature (canvas 2026-11-25: S6Tab, S7Tab, S8Tab, TabLargeText, TabLandRuler, FlowNote3Tab;
// line rules of TabOtherInstruments). One line per course, top line — the thinnest string; a digit — the fret,
// bars of 4 notes (4/4 in quarters), the tonic boxed in gold, the sounding note in an ivory circle, played notes
// at 35 %. Layout numbers are the canvas SVG's: lines from x 22, the first note 6 pt after the opening bar line.

/// One note of the tablature.
struct TabNote: Hashable {
    var course: Int
    var fret: Int
    /// Note name under the column («F♯»).
    var name: String
    var isTonic: Bool
}

/// Geometry of one tablature system (one SVG of the canvas).
struct TabLayout {
    /// The canvas has two generations of tab boards: the per-string boards (S6/S7/S8Tab — bar numbers 3 pt after the
    /// bar line, names 22 pt under the last line) and the Tab* boards (landscape, large text — numbers 4 pt after the
    /// middle between notes, names 24 pt under).
    enum Rule { case perString, tab }
    var rule: Rule = .perString
    var courses: Int
    /// Line names from the lowest course up.
    var labels: [String]
    var width: CGFloat = 350
    var spacing: CGFloat
    var fontSize: CGFloat
    var step: CGFloat = 37.5
    var firstX: CGFloat = 40
    var circleRadius: CGFloat = 10
    var notesPerBar = 4

    var topY: CGFloat { 24 }
    var lastY: CGFloat { topY + CGFloat(max(0, courses - 1)) * spacing }
    var namesY: CGFloat { lastY + (rule == .perString ? 22 : 24) }
    var height: CGFloat { lastY + (rule == .perString ? 30 : 34) }
    func y(course: Int) -> CGFloat { lastY - CGFloat(course) * spacing }
    func x(_ i: Int) -> CGFloat { firstX + CGFloat(i) * step }

    /// Canvas line spacing: 18 up to 6 strings, 14 for 7, 13 for 8, 12 beyond.
    static func spacing(courses: Int) -> CGFloat {
        courses <= 6 ? 18 : (courses == 7 ? 14 : (courses == 8 ? 13 : 12))
    }

    /// Digits 15 pt up to 6 strings, 13 pt from 7 (the canvas keeps the digit under the line spacing).
    static func fontSize(courses: Int) -> CGFloat { courses <= 6 ? 15 : 13 }

    /// Dark plate under a digit (hides the line): the canvas sizes it by the digit count.
    func plate(digits: Int) -> CGSize {
        CGSize(width: digits <= 1 ? 0.55 * fontSize + 3.85 : fontSize + 4 + CGFloat(digits - 2) * 0.55 * fontSize,
               height: (fontSize * 1.1 * 10).rounded() / 10)
    }

    /// Gold frame of the tonic: the plate + 4 pt, 1.4 × the digit size high.
    func tonicBox(digits: Int) -> CGSize {
        let p = plate(digits: digits)
        return CGSize(width: p.width + 4, height: (fontSize * 1.4 * 10).rounded() / 10)
    }
}

enum TabColors {
    static let gold = Color(hex: 0xe8b54a)
    static let goldPlate = Color(hex: 0x3d3320)
    static let plate = Color(hex: 0x0d0e10)
}

/// One system: lines with names, bar lines and numbers, the current column, digits and names under them.
struct TabSystemView: View {
    let layout: TabLayout
    let notes: [TabNote]
    /// Index (in this system) of the sounding note; notes before it are played (35 %).
    var current: Int?
    /// Number of the first bar.
    var firstBar = 1

    var body: some View {
        Canvas { ctx, size in
            let l = layout
            let tertiary = Theme.textTertiary
            // Lines, lowest first; names at x 4 (11 pt, central).
            for course in 0..<l.courses {
                let y = l.y(course: course)
                drawText(ctx, Typo.notes(l.labels[safe: course] ?? "", size: 11, fixed: true).foregroundColor(tertiary),
                         at: CGPoint(x: 4, y: y), anchor: .leading)
                ctx.stroke(line(22, y, l.width - 4, y), with: .color(.white.opacity(0.22)), lineWidth: 1)
            }
            let bars = max(1, Int((Double(notes.count) / Double(l.notesPerBar)).rounded(.up)))
            let start = l.firstX - 6
            let end = l.x(notes.count - 1) + l.step / 2
            ctx.stroke(line(start, l.topY, start, l.lastY), with: .color(.white.opacity(0.35)), lineWidth: 1)
            for bar in 0..<bars {
                let left: CGFloat = bar == 0 ? start : l.x(bar * l.notesPerBar) - l.step / 2
                if bar > 0 { ctx.stroke(line(left, l.topY, left, l.lastY), with: .color(.white.opacity(0.18)), lineWidth: 1) }
                let numberX: CGFloat = l.rule == .perString ? left + 3 : (l.x(bar * l.notesPerBar) - l.step / 2) + 4
                drawText(ctx, Text("\(firstBar + bar)").font(Typo.fixed(9)).foregroundColor(tertiary),
                         at: CGPoint(x: numberX, y: 9), anchor: .leading, baseline: true, size: 9)
            }
            ctx.stroke(line(end, l.topY, end, l.lastY), with: .color(.white.opacity(0.35)), lineWidth: 1)
            if let current, current < notes.count {
                let w = l.step - 2
                ctx.fill(Path(roundedRect: CGRect(x: l.x(current) - w / 2, y: 14, width: w, height: l.lastY + 10 - 14), cornerRadius: 6),
                         with: .color(Color(red: 246 / 255, green: 243 / 255, blue: 236 / 255, opacity: 0.07)))
            }
            for (i, n) in notes.enumerated() {
                let x = l.x(i), y = l.y(course: n.course)
                let played = current.map { i < $0 } ?? false
                let alpha = played ? 0.35 : 1.0
                let digits = String(n.fret).count
                let isCurrent = current == i
                if isCurrent {
                    ctx.fill(Path(ellipseIn: CGRect(x: x - l.circleRadius, y: y - l.circleRadius, width: 2 * l.circleRadius, height: 2 * l.circleRadius)),
                             with: .color(Theme.textPrimary))
                } else if n.isTonic {
                    let b = l.tonicBox(digits: digits)
                    let rect = CGRect(x: x - b.width / 2, y: y - b.height / 2, width: b.width, height: b.height)
                    ctx.fill(Path(roundedRect: rect, cornerRadius: 5), with: .color(TabColors.goldPlate))
                    ctx.stroke(Path(roundedRect: rect, cornerRadius: 5), with: .color(TabColors.gold.opacity(0.6 * alpha)), lineWidth: 1)
                } else {
                    let p = l.plate(digits: digits)
                    ctx.fill(Path(CGRect(x: x - p.width / 2, y: y - p.height / 2, width: p.width, height: p.height)), with: .color(TabColors.plate))
                }
                let color: Color = isCurrent ? Theme.background : (n.isTonic ? TabColors.gold : Theme.textPrimary)
                let weight: Typo.Weight = isCurrent || n.isTonic ? .bold : .medium
                drawText(ctx, Text("\(n.fret)").font(Typo.fixed(l.fontSize, weight)).foregroundColor(isCurrent ? color : color.opacity(alpha)),
                         at: CGPoint(x: x, y: y), anchor: .center)
                drawText(ctx, Typo.notes(n.name, size: 10, fixed: true).foregroundColor((n.isTonic ? TabColors.gold : tertiary).opacity(alpha)),
                         at: CGPoint(x: x, y: l.namesY), anchor: .center, baseline: true, size: 10)
            }
            _ = size
        }
        .frame(width: layout.width, height: layout.height)
        .accessibilityElement()
        .accessibilityLabel("Табулатура: \(layout.courses) струн")
    }
}

private func line(_ x1: CGFloat, _ y1: CGFloat, _ x2: CGFloat, _ y2: CGFloat) -> Path {
    var p = Path(); p.move(to: CGPoint(x: x1, y: y1)); p.addLine(to: CGPoint(x: x2, y: y2)); return p
}

/// Draws text like the SVG: `baseline` — the alphabetic baseline at `y` (Inter ascender 0.96875 em), otherwise the
/// text box centred on `y` (`dominant-baseline: central`).
private func drawText(_ ctx: GraphicsContext, _ text: Text, at p: CGPoint, anchor: UnitPoint, baseline: Bool = false, size: CGFloat = 0) {
    let resolved = ctx.resolve(text)
    if baseline {
        let top = p.y - 0.96875 * size
        ctx.draw(resolved, at: CGPoint(x: p.x, y: top), anchor: UnitPoint(x: anchor.x, y: 0))
    } else {
        ctx.draw(resolved, at: p, anchor: UnitPoint(x: anchor.x, y: 0.5))
    }
}

/// Position ruler (canvas SVG 350 × 48, viewBox from −6): ticks for every fret of the instrument (labels at the inlay
/// frets), the stretch of the path as a track, the current bar as an ivory thumb with «лады 4–9 · струна D» above.
struct TabRuler: View {
    var width: CGFloat = 350
    let fretCount: Int
    let pathMaxFret: Int
    let window: ClosedRange<Int>
    let title: String

    var body: some View {
        Canvas { ctx, _ in
            let k = (width - 20) / CGFloat(max(1, fretCount))
            func x(_ f: Int) -> CGFloat { 10 + CGFloat(f) * k }
            let dy: CGFloat = 6
            ctx.fill(Path(roundedRect: CGRect(x: 10, y: 12 + dy, width: CGFloat(pathMaxFret) * k, height: 6), cornerRadius: 3),
                     with: .color(.white.opacity(0.08)))
            let marks: Set<Int> = [0, 3, 5, 7, 9, 12, 15, 17, 19, 21, 24, 27]
            for f in 0...fretCount {
                let major = marks.contains(f)
                ctx.stroke(line(x(f), 22 + dy, x(f), (major ? 26 : 24) + dy), with: .color(.white.opacity(major ? 0.4 : 0.18)), lineWidth: 1)
                if major {
                    drawText(ctx, Text("\(f)").font(Typo.fixed(10)).foregroundColor(Theme.textTertiary),
                             at: CGPoint(x: x(f), y: 38 + dy), anchor: .center, baseline: true, size: 10)
                }
            }
            let thumb = CGRect(x: x(window.lowerBound) - 3, y: 9 + dy, width: CGFloat(window.upperBound - window.lowerBound) * k + 6, height: 12)
            ctx.fill(Path(roundedRect: thumb, cornerRadius: 6), with: .color(Color(red: 246 / 255, green: 243 / 255, blue: 236 / 255, opacity: 0.55)))
            drawText(ctx, Typo.notes(title, size: 10.5, weight: .semibold, fixed: true).foregroundColor(Theme.textPrimary),
                     at: CGPoint(x: thumb.midX, y: 5 + dy), anchor: .center, baseline: true, size: 10.5)
        }
        .frame(width: width, height: 48)
        .accessibilityElement()
        .accessibilityLabel("Позиция: \(title)")
    }
}

// MARK: Data from the controller

extension FretboardController {
    /// The tab replaces the neck and the tab bar (canvas S6Tab: full screen, back arrow in the header).
    var showsTabScreen: Bool { tabView && mode == .scale }

    /// The path as tab notes (a path is started when the tab opens without one — «4 ноты наискосок»).
    var tabNotes: [TabNote] {
        guard let app else { return [] }
        return pathNotes.map { n in
            let degree = scale.degreeIndex(of: n.pitch, tonic: settings.tonic)
            let name = degree.flatMap { spelled[safe: $0] }.map { app.formatter.string($0) } ?? app.chromaticName(n.pitch).filter { !$0.isNumber }
            return TabNote(course: n.course, fret: n.fret, name: name, isTonic: n.pitch.pitchClass == settings.tonic.pitchClass)
        }
    }

    /// Line names, lowest course first; the top line is in lower case when its letter repeats lower down («e»).
    var tabLineLabels: [String] {
        guard let app else { return [] }
        var names = app.tuning.spelledNotes.map { app.formatter.string($0.name) }
        if let top = names.last, names.dropLast().contains(top) { names[names.count - 1] = top.lowercased() }
        return names
    }

    /// «G · Мажор · путь»: the scale's short name (the canvas drops «(ионийский)»).
    var tabTitle: String {
        var title = scaleTitle
        if let open = title.range(of: " ("), title.hasSuffix(")") { title.removeSubrange(open.lowerBound..<title.endIndex) }
        return title + " · путь"
    }

    var pathKindTitle: String {
        switch pathKind {
        case .threePerString?: return "3 ноты на струну"
        case .oneString?: return "По одной струне"
        default: return "4 ноты наискосок"
        }
    }

    var pathKindShortTitle: String {
        switch pathKind {
        case .threePerString?: return "3 на струну"
        case .oneString?: return "по одной струне"
        default: return "4 наискосок"
        }
    }

    /// Opens the tab: makes sure there is a path to show.
    func openTab() {
        if pathKind == nil { pathStart = nil; pathKind = .fourDiagonal }
        tabView = true
    }

    /// Screenshot state of FlowNote3Tab: «A · I–V–vi–IV», the first chord, quarters.
    func progressionTabDemo() {
        mode = .progression   // takes the scale's key — the board's key is set after
        progression.templateId = "pop"
        // FlowNote1 → «Прогрессия от A»: from A on the 6th string, 5th fret (course 2 of 8), the hand at frets 5–9.
        progression.start(from: NeckSpot(course: max(0, (app?.instrument.courses.count ?? 6) - 6), fret: 5))
        progression.rhythm = .perBeat
        progression.loop = true
        tabView = true
    }
}

// MARK: Portrait screen (S6Tab, S7Tab, S8Tab, TabLargeText)

/// Full screen over the tab bar. Coordinates are the canvas's (390 × 844) shifted by the safe area (47 on the
/// reference phone): header 50, path row 104, ruler 150, systems from 204, legend 30 pt above the bottom edge.
struct FretTabScreen: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dynamicTypeSize) private var typeSize

    private var fretboard: FretboardController { app.fretboard }

    private var large: Bool {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-fretTabLarge") { return true }
        #endif
        return typeSize.isAccessibilitySize
    }

    var body: some View {
        let notes = fretboard.tabNotes
        let current = fretboard.pathIndex
        let perSystem = large ? 4 : 8
        let systems = stride(from: 0, to: notes.count, by: perSystem).map { Array(notes[$0..<min(notes.count, $0 + perSystem)]) }
        let courses = app.instrument.courses.count
        let layout = TabLayout(rule: large ? .tab : .perString, courses: courses, labels: fretboard.tabLineLabels,
                               spacing: large ? 21 : TabLayout.spacing(courses: courses),
                               fontSize: large ? 20 : TabLayout.fontSize(courses: courses),
                               step: large ? 73.5 : 37.5, firstX: large ? 46 : 40, circleRadius: large ? 11 : 10)
        let available: CGFloat = 610
        let gap: CGFloat = large ? 17 : (CGFloat(systems.count) * (layout.height + 52) <= available ? 52 : max(3, 152 - layout.height))
        GeometryReader { proxy in
        ZStack(alignment: .topLeading) {
            header.frame(width: 350, height: 44).offset(x: 20, y: 3)
            if large {
                HStack(spacing: 8) {
                    Typo.notes(windowTitle(notes, current), size: 17, weight: .semibold, fixed: true).foregroundStyle(Theme.textPrimary)
                        .lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
                    segments
                }
                .frame(width: 350).offset(x: 20, y: 61)
            } else {
                HStack(spacing: 8) {
                    Button { app.sheet = .fretPath } label: {
                        HeaderChip(text: fretboard.pathKindTitle, icon: .chevronDown, iconSize: 12)
                    }
                    .buttonStyle(PressableStyle())
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityLabel("Путь: \(fretboard.pathKindTitle)")
                    segments
                }
                .frame(width: 350).offset(x: 20, y: 57)
                let window = barWindow(notes, current)
                TabRuler(fretCount: app.instrument.fretCount, pathMaxFret: notes.map(\.fret).max() ?? 0,
                         window: window.frets, title: window.title)
                    .offset(x: 20, y: 103)
            }
            systemsScroll(systems: systems, layout: layout, gap: gap, perSystem: perSystem, current: current,
                          height: max(100, proxy.size.height - (large ? 113 : 157 + 30)))
                .offset(x: 0, y: large ? 113 : 157)
        }
        .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
        .overlay(alignment: .bottom) {
            if large {
                LinearGradient(colors: [TabColors.plate.opacity(0), TabColors.plate], startPoint: .top, endPoint: .bottom)
                    .frame(height: 60).allowsHitTesting(false)
            } else {
                HStack {
                    Text(notes.contains { $0.fret == 0 } ? "0 — открытая струна · черта — такт" : "цифра — лад · черта — такт")
                    Spacer(minLength: 8)
                    Typo.notes("тоника \(app.formatter.string(fretboard.settings.tonic)) — в рамке", size: 11, fixed: true)
                }
                .font(Typo.fixed(11)).foregroundStyle(Theme.textTertiary)
                .lineLimit(1)
                .frame(width: 350, height: 30, alignment: .topLeading)
            }
        }
        }
        .ignoresSafeArea(edges: .bottom)
    }

    private var header: some View {
        HStack(spacing: 10) {
            RoundIconButton(icon: .chevronLeft, size: 40, label: "Назад") { fretboard.tabView = false }
            VStack(alignment: .leading, spacing: 1) {
                Typo.notes(fretboard.tabTitle, size: 16, weight: .medium, fixed: true)
                    .foregroundStyle(Theme.textPrimary).lineLimit(1)
                Typo.notes(subtitle, size: 12, fixed: true).foregroundStyle(Theme.textTertiary).lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            PrimaryRoundButton(icon: fretboard.isPlaying ? .pause : .play, size: large ? 48 : 44, iconSize: 20,
                               label: fretboard.isPlaying ? "Пауза" : "Сыграть путь") { fretboard.togglePlayback() }
        }
    }

    private var subtitle: String {
        let n = fretboard.pathNotes.count
        let i = (fretboard.pathIndex ?? 0) + 1
        guard let first = fretboard.pathNotes.first else { return "\(i) / \(n)" }
        // Canvas: «от …» only when the path does not start on the tonic (S8Tab «от F♯1»; TabPortraitFull has none).
        if first.degreeIndex == 0 { return "\(i) / \(n)" }
        return "\(i) / \(n) · от \(app.chromaticName(first.pitch))"
    }

    private var segments: some View {
        Segments(options: [(false, "Гриф"), (true, "Таб")],
                 selection: Binding(get: { fretboard.tabView }, set: { fretboard.tabView = $0 }))
            .frame(width: 120)
    }

    /// Frets and string of the bar with the sounding note (the first bar before playing).
    private func barWindow(_ notes: [TabNote], _ current: Int?) -> (frets: ClosedRange<Int>, title: String) {
        let bar = (current ?? 0) / 4
        let slice = notes.dropFirst(bar * 4).prefix(4)
        guard let lo = slice.map(\.fret).min(), let hi = slice.map(\.fret).max() else { return (0...0, "") }
        let course = notes[safe: current ?? 0]?.course ?? slice.first?.course ?? 0
        let string = app.tuning.spelledNotes[safe: course].map { app.formatter.string($0.name) } ?? ""
        return (lo...hi, "лады \(lo)–\(hi) · струна \(string)")
    }

    private func windowTitle(_ notes: [TabNote], _ current: Int?) -> String { barWindow(notes, current).title }

    /// A short last system is narrower (canvas S7Tab: 205 pt for one bar), its notes a little wider apart.
    private func systemLayout(_ layout: TabLayout, count: Int, perSystem: Int) -> TabLayout {
        guard count < perSystem, !large, count > 0 else { return layout }
        var l = layout
        l.width = 30 + 350 * CGFloat(count) / CGFloat(perSystem)
        l.step = (l.width - 29.4 - l.firstX) / (CGFloat(count) - 0.5)
        return l
    }

    private func systemsScroll(systems: [[TabNote]], layout: TabLayout, gap: CGFloat, perSystem: Int, current: Int?, height: CGFloat) -> some View {
        ScrollViewReader { reader in
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: gap) {
                    ForEach(Array(systems.enumerated()), id: \.offset) { index, notes in
                        let start = index * perSystem
                        let local = current.flatMap { $0 >= start ? $0 - start : nil }
                        TabSystemView(layout: systemLayout(layout, count: notes.count, perSystem: perSystem), notes: notes, current: local.flatMap { $0 < notes.count ? $0 : nil } ?? (local != nil ? notes.count : nil),
                                      firstBar: start / 4 + 1)
                            // Coach mark «Как читать табулатуру» (Features/Tour): the sounding system, else the first.
                            .coachAnchor(index == (current.map { $0 / perSystem } ?? 0) ? CoachCatalog.Anchor.tabSystem : nil)
                            .padding(.leading, 20)
                            .id("tabsys-\(index)")
                    }
                }
                .padding(.bottom, 60)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollIndicators(.hidden)
            .frame(height: height)
            .onAppear { scroll(reader, current, perSystem, animated: false) }
            .onChange(of: current) { _, value in scroll(reader, value, perSystem, animated: true) }
        }
    }

    /// Keeps the sounding system in view: the system before it at the top (large text — the system itself).
    private func scroll(_ reader: ScrollViewProxy, _ current: Int?, _ perSystem: Int, animated: Bool) {
        guard let current else { return }
        let system = current / perSystem
        let target = large ? system : max(0, system - 1)
        if animated {
            withAnimation(Motion.out(Motion.Duration.move)) { reader.scrollTo("tabsys-\(target)", anchor: .top) }
        } else {
            reader.scrollTo("tabsys-\(target)", anchor: .top)
        }
    }
}

// MARK: Landscape (TabLandRuler, 844 × 390)

/// Header (top 16, from x 40, 764 wide): back 44, title 15 medium, path chip, «Гриф | Таб» 150, «10 / 32», play 48;
/// ruler 764 at top 80; the whole path in one system (8 bars) at top 132; legend 12 pt at top 362.
struct FretTabLandscape: View {
    @Environment(AppModel.self) private var app
    private var fretboard: FretboardController { app.fretboard }

    var body: some View {
        let notes = fretboard.tabNotes
        let current = fretboard.pathIndex
        let perSystem = 32
        let systems = stride(from: 0, to: notes.count, by: perSystem).map { Array(notes[$0..<min(notes.count, $0 + perSystem)]) }
        let courses = app.instrument.courses.count
        let layout = TabLayout(rule: .tab, courses: courses, labels: fretboard.tabLineLabels, width: 764,
                               spacing: courses <= 6 ? 28 : (courses == 7 ? 25 : 22), fontSize: 13, step: 88.75 / 4, firstX: 44)
        LandscapeCanvas {
            ZStack(alignment: .topLeading) {
                header.board(x: 40, y: 16, width: 764)
                let bar = (current ?? 0) / 4
                let slice = notes.dropFirst(bar * 4).prefix(4)
                let lo = slice.map(\.fret).min() ?? 0, hi = slice.map(\.fret).max() ?? 0
                let course = notes[safe: current ?? 0]?.course ?? 0
                let string = app.tuning.spelledNotes[safe: course].map { app.formatter.string($0.name) } ?? ""
                TabRuler(width: 764, fretCount: app.instrument.fretCount, pathMaxFret: notes.map(\.fret).max() ?? 0,
                         window: lo...hi, title: "лады \(lo)–\(hi) · струна \(string)")
                    .board(x: 40, y: 80)
                ScrollView(.vertical) {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(Array(systems.enumerated()), id: \.offset) { index, part in
                            let start = index * perSystem
                            let local = current.flatMap { $0 >= start ? $0 - start : nil }
                            TabSystemView(layout: layout, notes: part, current: local.flatMap { $0 < part.count ? $0 : nil } ?? (local != nil ? part.count : nil),
                                          firstBar: start / 4 + 1)
                        }
                    }
                }
                .scrollIndicators(.hidden)
                .frame(width: 764, height: 226)
                .board(x: 40, y: 132)
                HStack {
                    Text(notes.contains { $0.fret == 0 } ? "0 — открытая струна · черта — такт (4 ноты = такт 4/4, четвертями) · номер такта сверху"
                                                         : "цифра — лад · черта — такт (4 ноты = такт 4/4, четвертями) · номер такта сверху")
                    Spacer(minLength: 8)
                    Typo.notes("тоника \(app.formatter.string(fretboard.settings.tonic)) — в рамке", size: 12, fixed: true)
                }
                .font(Typo.fixed(12)).foregroundStyle(Theme.textTertiary).lineLimit(1)
                .board(x: 40, y: 362, width: 764)
            }
            .frame(width: 844, height: 390, alignment: .topLeading)
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            RoundIconButton(icon: .chevronLeft, size: 44, label: "Назад") { fretboard.tabView = false }
            Typo.notes(fretboard.tabTitle, size: 15, weight: .medium, fixed: true).foregroundStyle(Theme.textPrimary).lineLimit(1)
            Button { app.sheet = .fretPath } label: {
                HeaderChip(text: fretboard.pathKindShortTitle, icon: .chevronDown, iconSize: 12)
            }
            .buttonStyle(PressableStyle())
            Spacer(minLength: 0)
            Segments(options: [(false, "Гриф"), (true, "Таб")],
                     selection: Binding(get: { fretboard.tabView }, set: { fretboard.tabView = $0 }))
                .frame(width: 150)
            Chip(text: "\((fretboard.pathIndex ?? 0) + 1) / \(fretboard.pathNotes.count)", style: .muted)
            PrimaryRoundButton(icon: fretboard.isPlaying ? .pause : .play, size: 48, iconSize: 20,
                               label: fretboard.isPlaying ? "Пауза" : "Сыграть путь") { fretboard.togglePlayback() }
        }
        .frame(height: 48)
    }
}

// MARK: Progression as a chord tab (FlowNote3Tab)

/// Below the progression row (canvas top 210): «Где на грифе: лады 5–11 · …», the chord tab (350 × 208 at 236: a
/// column of 75 pt per chord, name 15 semibold and numeral 10 above, digits 14, the chord root boxed), the «Ритм /
/// Повторять» card at 500 and «Такт 1 из 4 · A» with «Сыграть» at 686. The view starts right under the row (18 pt
/// above the caption).
struct ProgressionTabBody: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        let p = app.fretboard.progression
        ZStack(alignment: .topLeading) {
            caption(p).frame(width: 350, alignment: .leading)
            ProgressionTabTable().offset(y: 26)
            CardGroup {
                Button { app.sheet = .fretProgression } label: {
                    CardRow(title: "Ритм", minHeight: 50) {
                        HStack(spacing: 8) {
                            Text(rhythmTitle(p.rhythm))
                            Icon(.chevronRight, size: 16, color: Theme.textSecondary)
                        }
                    }
                }
                .buttonStyle(.plain)
                CardRow(title: "Повторять", minHeight: 50) {
                    ToggleSwitch(isOn: Binding(get: { p.loop }, set: { p.loop = $0 }), label: "Повторять")
                }
            }
            .frame(width: 350)
            .offset(y: 290)
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Typo.notes("Такт \(p.current + 1) из \(p.voiced.count) · \(chordName(p.voiced[safe: p.current]))", size: 14, weight: .medium)
                        .foregroundStyle(Theme.textPrimary).lineLimit(1)
                    Text("в рамке — тоника аккорда").font(Typo.inter(12)).foregroundStyle(Theme.textTertiary).lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Button { p.toggle() } label: {
                    HStack(spacing: 8) {
                        Icon(p.isPlaying ? .pause : .play, size: 18, color: Theme.background)
                        Text(p.isPlaying ? "Пауза" : "Сыграть").font(Typo.inter(16, .semibold)).foregroundStyle(Theme.background)
                    }
                    .padding(.leading, 14).padding(.trailing, 18)
                    .frame(height: 52)
                    .background(Capsule().fill(Theme.textPrimary))
                    .shadow(color: .black.opacity(0.35), radius: 9, y: 6)
                    .fixedSize()
                }
                .buttonStyle(PressableStyle())
                .accessibilityLabel(p.isPlaying ? "Пауза" : "Сыграть прогрессию")
            }
            .frame(width: 350)
            .offset(y: 476)
        }
        .frame(width: 350, height: 528, alignment: .topLeading)
        .padding(.top, 18)   // under the 38 pt progression row (canvas: row 154, caption 210)
    }

    private func chordName(_ v: VoicedChord?) -> String {
        guard let v else { return "" }
        return compactChordName(v.chord.name(root: v.root, formatter: app.formatter))
    }

    private func rhythmTitle(_ r: StrumRhythm) -> String {
        let m = app.settings.metronome.meter
        let base: String
        switch r {
        case .perBar: base = "по тактам"
        case .perBeat: base = "по четвертям"
        case .downUpEighths: base = "восьмыми вниз-вверх"
        }
        return "\(base) · \(m.numerator)/\(m.denominator)"
    }

    private func caption(_ p: ProgressionController) -> some View {
        let frets = p.voiced.compactMap(\.voicing).flatMap(\.notes).map(\.fret).filter { $0 > 0 }
        let lo = frets.min() ?? 0, hi = frets.max() ?? 0
        let n = p.voiced.count
        let word = n % 10 == 1 && n % 100 != 11 ? "аккорд" : ((2...4).contains(n % 10) && !(12...14).contains(n % 100) ? "аккорда" : "аккордов")
        let tail = hi - lo <= 7 ? " · все \(n) \(word) рядом, без прыжков" : " · рука переходит по грифу"
        return (Text("Где на грифе: ") + Text("лады \(lo)–\(hi)").foregroundColor(Theme.textPrimary) + Text(tail))
            .font(Typo.inter(12)).foregroundStyle(Theme.textTertiary)
            .padding(.leading, 2)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// The chord tab itself: one column per chord.
struct ProgressionTabTable: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        let p = app.fretboard.progression
        let courses = app.instrument.courses.count
        let labels = app.fretboard.tabLineLabels
        let spacing: CGFloat = 22
        let top: CGFloat = 40
        let last = top + CGFloat(courses - 1) * spacing
        let count = max(1, p.voiced.count)
        let colW = 300 / CGFloat(count)
        let names = p.voiced.map { compactChordName($0.chord.name(root: $0.root, formatter: app.formatter)) }
        let numerals = p.progression.chords.map(\.numeral)
        Canvas { ctx, _ in
            for course in 0..<courses {
                let y = last - CGFloat(course) * spacing
                drawText(ctx, Typo.notes(labels[safe: course] ?? "", size: 11, fixed: true).foregroundColor(Theme.textTertiary),
                         at: CGPoint(x: 6, y: y), anchor: .leading)
                ctx.stroke(line(28, y, 346, y), with: .color(.white.opacity(0.2)), lineWidth: 1)
            }
            for i in 0...count {
                let x = 32 + CGFloat(i) * colW
                ctx.stroke(line(x, top, x, last), with: .color(.white.opacity(i == 0 || i == count ? 0.35 : 0.2)), lineWidth: 1)
            }
            for (i, v) in p.voiced.enumerated() {
                let cx = 32 + colW * (CGFloat(i) + 0.5)
                let isCurrent = i == p.current
                if isCurrent {
                    ctx.fill(Path(roundedRect: CGRect(x: cx - colW / 2 + 6, y: 6, width: colW - 12, height: last + 8), cornerRadius: 8),
                             with: .color(Color(red: 246 / 255, green: 243 / 255, blue: 236 / 255, opacity: 0.07)))
                }
                drawText(ctx, Typo.notes(names[i], size: 15, weight: .semibold, fixed: true).foregroundColor(isCurrent ? Theme.textPrimary : Theme.textBody),
                         at: CGPoint(x: cx, y: 22), anchor: .center, baseline: true, size: 15)
                drawText(ctx, Typo.notes(numerals[safe: i] ?? "", size: 10, fixed: true).foregroundColor(Theme.textTertiary),
                         at: CGPoint(x: cx, y: 34), anchor: .center, baseline: true, size: 10)
                guard let voicing = v.voicing else { continue }
                for n in voicing.notes {
                    let y = last - CGFloat(n.course) * spacing
                    let digits = String(n.fret).count
                    let root = n.pitch.pitchClass == v.root.pitchClass
                    if root {
                        let w: CGFloat = digits == 1 ? 16 : 23
                        let rect = CGRect(x: cx - w / 2, y: y - 8.5, width: w, height: 17)
                        ctx.fill(Path(roundedRect: rect, cornerRadius: 5), with: .color(TabColors.goldPlate))
                        ctx.stroke(Path(roundedRect: rect, cornerRadius: 5), with: .color(TabColors.gold.opacity(0.6)), lineWidth: 1)
                    } else {
                        let w: CGFloat = digits == 1 ? 12 : 19
                        ctx.fill(Path(CGRect(x: cx - w / 2, y: y - 7, width: w, height: 14)), with: .color(TabColors.plate))
                    }
                    drawText(ctx, Text("\(n.fret)").font(Typo.fixed(14, root ? .bold : .medium)).foregroundColor(root ? TabColors.gold : Theme.textPrimary),
                             at: CGPoint(x: cx, y: y), anchor: .center)
                }
            }
        }
        .frame(width: 350, height: last + 14)
        .accessibilityElement()
        .accessibilityLabel("Табулатура аккордов: " + names.joined(separator: ", "))
    }
}
