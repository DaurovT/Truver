import Foundation
import SwiftUI

/// The trainer's neck (corrected canvas, «Тренажёр грифа»): flat and dark like Guitar Pro — graphite board, metal
/// fret wires, blue-grey strings, round inlays — fret numbers on the left and a scroll bar on the right. A 350 pt
/// block: numbers 0–18, the 310 pt board from 22, the bar at 346. The window shows `lower…upper` frets (the wire
/// before `lower` at the top edge, the centre of wire `upper` at the bottom edge); the whole neck scrolls.
struct TrainerNeck: View {
    struct Dot: Equatable {
        enum Style: Equatable { case question, right(small: Bool) }
        var course: Int
        var fret: Int
        var label: String
        var style: Style
    }

    struct Highlight: Equatable {
        var course: Int
        var right: Bool
    }

    let courses: Int
    let fretCount: Int
    let lower: Int
    let upper: Int
    let height: CGFloat
    var leftHanded = false
    var dots: [Dot] = []
    var highlight: Highlight?

    @State private var scroll: CGFloat?
    @State private var dragFrom: CGFloat?

    static let width: CGFloat = 350
    static let boardX: CGFloat = 22
    static let boardWidth: CGFloat = 310
    static let stringWidths: [CGFloat] = [4.4, 4.0, 3.6, 3.1, 2.7, 2.3, 1.9, 1.6, 1.25, 1.0]

    /// Geometry of the canvas board: wire n's centre at `L·(1 − 2^(−n/12)) − 0.8` along the neck.
    struct Geometry {
        let courses: Int
        let fretCount: Int
        let lower: Int
        let upper: Int
        let height: CGFloat
        let leftHanded: Bool

        static func d(_ n: Double) -> Double { 1 - pow(2, -n / 12) }
        var scale: CGFloat { (height + 0.8) / CGFloat(Self.d(Double(upper)) - Self.d(Double(lower - 1))) }
        var initialScroll: CGFloat { scale * CGFloat(Self.d(Double(lower - 1))) }
        var maxScroll: CGFloat { max(initialScroll, scale * CGFloat(Self.d(Double(fretCount))) + 12 - height) }
        /// Centre of wire n in content coordinates (wire 0 is the nut's place).
        func wire(_ n: Int) -> CGFloat { scale * CGFloat(Self.d(Double(n))) - 0.8 }
        func cell(_ fret: Int) -> CGFloat { fret == 0 ? 5 : (wire(fret - 1) + wire(fret)) / 2 }
        /// Fractional fret at a content y.
        func fret(at y: CGFloat) -> CGFloat { CGFloat(-12 * log2(max(1e-6, 1 - Double(y / scale)))) }
        /// String centre in board coordinates (the inner board starts at 4, strings 26 in from its sides).
        func x(course: Int) -> CGFloat {
            let spacing = courses > 1 ? (Self.inner - 52) / CGFloat(courses - 1) : 0
            let index = leftHanded ? courses - 1 - course : course
            return 4 + 26 + CGFloat(index) * spacing
        }
        static let inner: CGFloat = 302
    }

    var body: some View {
        let g = Geometry(courses: courses, fretCount: fretCount, lower: lower, upper: upper, height: height, leftHanded: leftHanded)
        let s = scroll ?? g.initialScroll
        ZStack(alignment: .topLeading) {
            labels(g, s)
            board(g, s).offset(x: Self.boardX)
            ForEach(Array(dots.enumerated()), id: \.offset) { _, dot in
                noteDot(dot).position(x: Self.boardX + g.x(course: dot.course), y: g.cell(dot.fret) - s)
            }
            if s > 0.5 {
                LinearGradient(colors: [Color(hex: 0x0d0e10), Color(hex: 0x0d0e10, opacity: 0)], startPoint: .top, endPoint: .bottom)
                    .frame(width: Self.boardWidth, height: 26).offset(x: Self.boardX)
            }
            LinearGradient(colors: [Color(hex: 0x0d0e10, opacity: 0), Color(hex: 0x0d0e10)], startPoint: .top, endPoint: .bottom)
                .frame(width: Self.boardWidth, height: 30).offset(x: Self.boardX, y: height - 30)
            if let highlight {
                // Canvas: 30 × height with a 1 pt border outside (content box), left at the string − 15.
                RoundedRectangle(cornerRadius: 16)
                    .fill(highlight.right ? Theme.inTune.opacity(0.08) : Color(hex: 0x8fc4ff, opacity: 0.10))
                    .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color(hex: 0x8fc4ff, opacity: 0.35), lineWidth: 1))
                    .frame(width: 32, height: height + 2)
                    .offset(x: Self.boardX + g.x(course: highlight.course) - 15)
            }
            scrollBar(g, s)
        }
        .frame(width: Self.width, height: height, alignment: .topLeading)
        .contentShape(Rectangle())
        .gesture(DragGesture(minimumDistance: 4)
            .onChanged { v in
                let from = dragFrom ?? s
                if dragFrom == nil { dragFrom = s }
                scroll = min(g.maxScroll, max(0, from - v.translation.height))
            }
            .onEnded { _ in dragFrom = nil })
    }

    private func labels(_ g: Geometry, _ s: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            ForEach(1...max(1, fretCount), id: \.self) { fret in
                let y = g.cell(fret) - s
                if y > 2, y < height - 2 {
                    let inlay = [3, 5, 7, 9, 12, 15, 17, 19, 21, 24].contains(fret)
                    Text("\(fret)")
                        .font(Typo.inter(11, [5, 12, 17, 24].contains(fret) ? .semibold : .regular))
                        .foregroundStyle(inlay ? Theme.textSecondary : Color.white.opacity(0.22))
                        .frame(width: 18, alignment: .trailing)
                        .position(x: 9, y: y)
                }
            }
        }
        .frame(width: Self.width, height: height, alignment: .topLeading)
    }

    private func board(_ g: Geometry, _ s: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            // 0 0 0 1px rgba(0,0,0,0.6): a ring just outside the board; 0 30px 60px rgba(0,0,0,0.8) under it.
            RoundedRectangle(cornerRadius: 5).strokeBorder(Color.black.opacity(0.6), lineWidth: 1)
                .frame(width: Self.boardWidth + 2, height: height + 2).offset(x: -1, y: -1)
            RoundedRectangle(cornerRadius: 4).fill(Color(hex: 0x3a404a))
                .shadow(color: .black.opacity(0.8), radius: 30, y: 30)
                .frame(width: Self.boardWidth, height: height)
            Canvas { ctx, size in
                let inner = CGRect(x: 4, y: 0, width: Geometry.inner, height: size.height)
                ctx.clip(to: Path(inner))
                ctx.fill(Path(inner), with: .color(Color(hex: 0x2b2f36)))
                // Inlays: one in the middle, two at 12 and 24.
                for fret in [3, 5, 7, 9, 12, 15, 17, 19, 21, 24] where fret <= fretCount {
                    let y = g.cell(fret) - s
                    guard y > -10, y < size.height + 10 else { continue }
                    let xs: [CGFloat] = fret % 12 == 0 ? [4 + 90, 4 + 211] : [4 + 151]
                    for x in xs {
                        ctx.fill(Path(ellipseIn: CGRect(x: x - 5, y: y - 5, width: 10, height: 10)), with: .color(Color(hex: 0xaab3c0, opacity: 0.4)))
                    }
                }
                let wire = Gradient(colors: [Color(hex: 0x6b7380), Color(hex: 0xe3e8ef), Color(hex: 0x6b7380)])
                for n in 1...max(1, fretCount) {
                    let y = g.wire(n) - 2 - s
                    guard y > -6, y < size.height + 2 else { continue }
                    let rect = CGRect(x: 4, y: y, width: Geometry.inner, height: 4)
                    ctx.fill(Path(roundedRect: rect, cornerRadius: 2),
                             with: .linearGradient(wire, startPoint: CGPoint(x: 0, y: y), endPoint: CGPoint(x: 0, y: y + 4)))
                }
                let widths = Array(TrainerNeck.stringWidths.suffix(courses))
                for course in 0..<courses {
                    let w = course < widths.count ? widths[course] : 1
                    let plain = course >= courses - 2
                    let x = g.x(course: course)
                    ctx.fill(Path(CGRect(x: x - w / 2, y: 0, width: w, height: size.height)),
                             with: .color(Color(hex: plain ? 0xb8c5d6 : 0x9fb0c6)))
                }
                // Nut over the strings (0 4px 6px rgba(0,0,0,0.6)).
                if s < 12 {
                    var shadowed = ctx
                    shadowed.addFilter(.shadow(color: .black.opacity(0.6), radius: 3, x: 0, y: 4))
                    shadowed.fill(Path(CGRect(x: 4, y: -s, width: Geometry.inner, height: 10)), with: .color(Color(hex: 0xdfe5ec)))
                }
            }
            .frame(width: Self.boardWidth, height: height)
        }
        .frame(width: Self.boardWidth, height: height, alignment: .topLeading)
    }

    @ViewBuilder private func noteDot(_ dot: Dot) -> some View {
        let size: CGFloat = dot.style == .right(small: true) ? 36 : 38
        let right = dot.style != .question
        Typo.notes(dot.label, size: 12, weight: .bold)
            .foregroundStyle(Color(hex: 0x0c0d0f))
            .frame(width: size, height: size)
            .background(Circle().fill(right ? Theme.inTune.opacity(0.95) : Color(hex: 0xf6f3ec, opacity: 0.98)))
            .overlay(Circle().strokeBorder(right ? Color(hex: 0xb8f5d2) : .white, lineWidth: 1.5))
            .shadow(color: .black.opacity(0.55), radius: 7, y: 6)
    }

    private func scrollBar(_ g: Geometry, _ s: CGFloat) -> some View {
        let top = g.fret(at: s), bottom = g.fret(at: s + height)
        let total = CGFloat(max(1, fretCount))
        let thumbTop = max(0, top) / total * height
        let thumbHeight = min(height - thumbTop, max(12, (bottom - max(0, top)) / total * height))
        return ZStack(alignment: .top) {
            RoundedRectangle(cornerRadius: 2).fill(Color.white.opacity(0.08)).frame(width: 4, height: height)
            RoundedRectangle(cornerRadius: 2).fill(Color(hex: 0xf6f3ec, opacity: 0.6)).frame(width: 4, height: thumbHeight)
                .offset(y: thumbTop)
        }
        .frame(width: 4, height: height, alignment: .top)
        .offset(x: Self.width - 4)
    }
}
