import SwiftUI
import TruverTheory

/// Geometry of the drawn neck. Horizontal: frets along x (landscape, FB-1). Vertical: frets along y (portrait).
struct NeckGeometry {
    var horizontal: Bool
    var courses: Int
    var frets: Int
    var fretSpacing: CGFloat
    var stringSpacing: CGFloat
    /// Physical low string drawn at the bottom (horizontal) / left (vertical) unless flipped.
    var lowStringOnTop: Bool
    var leftHanded: Bool

    var openArea: CGFloat { fretSpacing * 0.75 }
    var margin: CGFloat { stringSpacing * 0.7 }

    var size: CGSize {
        let along = openArea + CGFloat(frets) * fretSpacing + 12
        let across = CGFloat(max(1, courses - 1)) * stringSpacing + 2 * margin + 18
        return horizontal ? CGSize(width: along, height: across) : CGSize(width: across, height: along)
    }

    /// Distance along the neck of the nut line.
    var nut: CGFloat { openArea }

    func along(fret: Int) -> CGFloat {
        fret == 0 ? openArea * 0.45 : nut + (CGFloat(fret) - 0.5) * fretSpacing
    }

    func fretLine(_ fret: Int) -> CGFloat { nut + CGFloat(fret) * fretSpacing }

    func across(course: Int) -> CGFloat {
        // Horizontal: low string at the bottom (as on the instrument, tab-like when flipped).
        let index = horizontal ? (lowStringOnTop ? course : courses - 1 - course)
                               : (lowStringOnTop ? courses - 1 - course : course)
        return margin + CGFloat(index) * stringSpacing
    }

    func point(course: Int, fret: Int) -> CGPoint {
        var a = along(fret: fret)
        if leftHanded { a = size.width(horizontal) - a }
        let c = across(course: course)
        return horizontal ? CGPoint(x: a, y: c) : CGPoint(x: c, y: a)
    }

    func alongPoint(_ value: CGFloat) -> CGFloat { leftHanded ? size.width(horizontal) - value : value }

    /// Nearest grid cell to a touch (FB-18: hit by nearest dot, not by its drawn size).
    func cell(at location: CGPoint) -> (course: Int, fret: Int) {
        var a = horizontal ? location.x : location.y
        if leftHanded { a = size.width(horizontal) - a }
        let c = horizontal ? location.y : location.x
        let fret: Int = a < nut ? 0 : min(frets, max(1, Int((a - nut) / fretSpacing) + 1))
        let course = (0..<courses).min { abs(across(course: $0) - c) < abs(across(course: $1) - c) } ?? 0
        return (course, fret)
    }
}

private extension CGSize {
    func width(_ horizontal: Bool) -> CGFloat { horizontal ? width : height }
}

/// The neck (FB-1…FB-3, FB-18, FB-19): drawn with Canvas, scrolls along the neck, pinch zooms, tap plays,
/// long tap hides/adds a note.
struct NeckView: View {
    @Environment(AppModel.self) private var app
    let horizontal: Bool
    let availableAcross: CGFloat
    @Binding var zoom: CGFloat
    let scrollTarget: Int?

    @GestureState private var pinch: CGFloat = 1

    var body: some View {
        let fretboard = app.fretboard
        let s = fretboard.settings
        let courses = app.instrument.courses.count
        let stringSpacing = max(30, min(52, (availableAcross - 40) / CGFloat(max(1, courses))))
        let geometry = NeckGeometry(horizontal: horizontal, courses: courses, frets: app.instrument.fretCount,
                                    fretSpacing: 58 * zoom * pinch, stringSpacing: stringSpacing,
                                    lowStringOnTop: s.lowStringOnTop, leftHanded: s.leftHanded)
        let cells = fretboard.cells()

        ScrollViewReader { proxy in
            ScrollView(horizontal ? .horizontal : .vertical, showsIndicators: false) {
                ZStack(alignment: .topLeading) {
                    Canvas { context, _ in
                        draw(context: &context, geometry: geometry, cells: cells)
                    }
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    anchors(geometry)
                }
                .contentShape(Rectangle())
                .onTapGesture(coordinateSpace: .local) { location in
                    let cell = geometry.cell(at: location)
                    fretboard.tap(course: cell.course, fret: cell.fret)
                }
                .simultaneousGesture(
                    LongPressGesture(minimumDuration: 0.45)
                        .sequenced(before: DragGesture(minimumDistance: 0, coordinateSpace: .local))
                        .onEnded { value in
                            if case .second(true, let drag?) = value {
                                let cell = geometry.cell(at: drag.location)
                                fretboard.toggle(course: cell.course, fret: cell.fret)
                            }
                        }
                )
            }
            .simultaneousGesture(
                MagnificationGesture()
                    .updating($pinch) { value, state, _ in state = value }
                    .onEnded { value in zoom = min(1.8, max(0.6, zoom * value)) }
            )
            .onChange(of: scrollTarget) { _, target in
                guard let target else { return }
                withAnimation(.easeInOut(duration: 0.3)) { proxy.scrollTo(target, anchor: horizontal ? .leading : .top) }
            }
            .onAppear {
                if let scrollTarget { proxy.scrollTo(scrollTarget, anchor: horizontal ? .leading : .top) }
            }
        }
        .accessibilityLabel("Гриф")
    }

    /// Invisible per-fret anchors for scrolling to a position (FB-6).
    private func anchors(_ g: NeckGeometry) -> some View {
        let lead = max(0, g.nut - g.fretSpacing)
        return Group {
            if g.horizontal {
                HStack(spacing: 0) {
                    Color.clear.frame(width: lead)
                    ForEach(0...g.frets, id: \.self) { fret in Color.clear.frame(width: g.fretSpacing).id(fret) }
                }
            } else {
                VStack(spacing: 0) {
                    Color.clear.frame(height: lead)
                    ForEach(0...g.frets, id: \.self) { fret in Color.clear.frame(height: g.fretSpacing).id(fret) }
                }
            }
        }
        .allowsHitTesting(false)
    }

    private func draw(context: inout GraphicsContext, geometry g: NeckGeometry, cells: [NeckCell]) {
        let size = g.size
        let firstString = g.across(course: 0), lastString = g.across(course: g.courses - 1)
        let acrossMin = min(firstString, lastString) - g.stringSpacing * 0.5
        let acrossMax = max(firstString, lastString) + g.stringSpacing * 0.5

        func rect(alongFrom a0: CGFloat, to a1: CGFloat, acrossFrom c0: CGFloat, to c1: CGFloat) -> CGRect {
            let x0 = g.alongPoint(a0), x1 = g.alongPoint(a1)
            return g.horizontal
                ? CGRect(x: min(x0, x1), y: c0, width: abs(x1 - x0), height: c1 - c0)
                : CGRect(x: c0, y: min(x0, x1), width: c1 - c0, height: abs(x1 - x0))
        }
        func line(along a: CGFloat, from c0: CGFloat, to c1: CGFloat) -> Path {
            var p = Path()
            let x = g.alongPoint(a)
            if g.horizontal { p.move(to: CGPoint(x: x, y: c0)); p.addLine(to: CGPoint(x: x, y: c1)) }
            else { p.move(to: CGPoint(x: c0, y: x)); p.addLine(to: CGPoint(x: c1, y: x)) }
            return p
        }
        func stringLine(across c: CGFloat) -> Path {
            var p = Path()
            let a0 = g.alongPoint(g.nut), a1 = g.alongPoint(g.fretLine(g.frets))
            if g.horizontal { p.move(to: CGPoint(x: a0, y: c)); p.addLine(to: CGPoint(x: a1, y: c)) }
            else { p.move(to: CGPoint(x: c, y: a0)); p.addLine(to: CGPoint(x: c, y: a1)) }
            return p
        }

        // Wood and inlays.
        context.fill(Path(roundedRect: rect(alongFrom: g.nut, to: g.fretLine(g.frets), acrossFrom: acrossMin, to: acrossMax),
                          cornerRadius: 4), with: .color(Theme.wood))
        let inlays = [3, 5, 7, 9, 15, 17, 19, 21]
        let middle = (acrossMin + acrossMax) / 2
        for fret in 1...g.frets {
            let a = g.alongPoint(g.along(fret: fret))
            let dots: [CGFloat] = fret % 12 == 0 ? [middle - g.stringSpacing, middle + g.stringSpacing]
                : inlays.contains(fret) ? [middle] : []
            for c in dots {
                let center = g.horizontal ? CGPoint(x: a, y: c) : CGPoint(x: c, y: a)
                context.fill(Path(ellipseIn: CGRect(x: center.x - 5, y: center.y - 5, width: 10, height: 10)),
                             with: .color(.white.opacity(0.12)))
            }
        }
        // Capo.
        if app.instrument.capo > 0 {
            let a = g.fretLine(app.instrument.capo) - g.fretSpacing * 0.5
            context.fill(Path(roundedRect: rect(alongFrom: a - 5, to: a + 5, acrossFrom: acrossMin, to: acrossMax), cornerRadius: 4),
                         with: .color(.white.opacity(0.25)))
        }
        // Frets and nut.
        for fret in 0...g.frets {
            context.stroke(line(along: g.fretLine(fret), from: acrossMin, to: acrossMax),
                           with: .color(fret == 0 ? .white.opacity(0.85) : Theme.fretWire), lineWidth: fret == 0 ? 5 : 1.5)
        }
        // Fret numbers («Лады от капо»: counted from the capo).
        let shift = app.fretboard.fretsFromCapo ? app.instrument.capo : 0
        for fret in [1, 3, 5, 7, 9, 12, 15, 17, 19, 21, 24] where fret <= g.frets && fret >= shift {
            let a = g.alongPoint(g.along(fret: fret))
            let position = g.horizontal ? CGPoint(x: a, y: acrossMax + 9) : CGPoint(x: acrossMax + 9, y: a)
            context.draw(Text("\(fret - shift)").font(.caption2).foregroundStyle(Theme.textSecondary), at: position)
        }
        // Strings: thicker towards the bass.
        for course in 0..<g.courses {
            let width = 1 + CGFloat(g.courses - 1 - course) / CGFloat(max(1, g.courses - 1)) * 1.8
            context.stroke(stringLine(across: g.across(course: course)), with: .color(Theme.stringColor.opacity(0.8)), lineWidth: width)
        }
        // Notes.
        let radius = max(13, min(g.stringSpacing, g.fretSpacing) * 0.4)
        for cell in cells {
            let center = g.point(course: cell.course, fret: cell.fret)
            let r = cell.isPlaying ? radius * 1.2 : radius
            let circle = Path(ellipseIn: CGRect(x: center.x - r, y: center.y - r, width: 2 * r, height: 2 * r))
            let color = Theme.color(for: cell.role)
            if cell.emphasis == .faint {
                context.stroke(circle, with: .color(color.opacity(0.35)), lineWidth: 1.5)
            } else {
                context.fill(circle, with: .color(cell.isAdded ? color.opacity(0.35) : color))
                if cell.isPlaying { context.stroke(circle, with: .color(.white), lineWidth: 3) }
            }
            if !cell.label.isEmpty {
                let textColor: Color = cell.emphasis == .faint ? color.opacity(0.6) : .black
                context.draw(Text(cell.label).font(.system(size: r * 0.78, weight: .bold, design: .rounded)).foregroundStyle(textColor),
                             at: center)
            }
        }
        _ = size
    }
}
