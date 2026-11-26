import SwiftUI

/// Stroke icons drawn on the canvas's 24 × 24 grid (same outlines as the design).
enum AppIcon {
    case tuner, fretboard, metronome, practice, gear, mic, micOff, waveform
    case chevronDown, chevronRight, chevronLeft, plus, minus, play, stop, check, list, sliders
    case close, timer, arrowUp, warning, refresh, trash, rename, search, pause, lock, music, repeatArrows, bluetooth, route, expand, strobe
    /// Audio interface (canvas «Вход переключён»): a box with a jack.
    case audioInterface

    var filled: Bool { self == .play || self == .stop || self == .pause }
}

struct IconShape: Shape {
    let icon: AppIcon

    func path(in rect: CGRect) -> Path {
        let s = min(rect.width, rect.height) / 24
        let ox = rect.midX - 12 * s, oy = rect.midY - 12 * s
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: ox + x * s, y: oy + y * s) }
        var path = Path()
        func line(_ points: [(CGFloat, CGFloat)], close: Bool = false) {
            guard let first = points.first else { return }
            path.move(to: p(first.0, first.1))
            for point in points.dropFirst() { path.addLine(to: p(point.0, point.1)) }
            if close { path.closeSubpath() }
        }
        func arc(cx: CGFloat, cy: CGFloat, r: CGFloat, from: Double, to: Double, clockwise: Bool) {
            path.addArc(center: p(cx, cy), radius: r * s, startAngle: .degrees(from), endAngle: .degrees(to), clockwise: clockwise)
        }
        switch icon {
        case .tuner:
            path.move(to: p(4, 16)); arc(cx: 12, cy: 16, r: 8, from: 180, to: 0, clockwise: false)
            line([(12, 16), (15, 10)])
        case .fretboard:
            path.addRoundedRect(in: CGRect(x: ox + 7 * s, y: oy + 3 * s, width: 10 * s, height: 18 * s), cornerSize: CGSize(width: 2 * s, height: 2 * s))
            for y in [8.0, 13, 18] { line([(7, y), (17, y)]) }
        case .metronome:
            line([(8, 21), (16, 21), (13.5, 4), (10.5, 4)], close: true)
            line([(12, 15), (17, 8)])
        case .practice:
            line([(4, 19), (4, 9)]); line([(10, 19), (10, 5)]); line([(16, 19), (16, 12)]); line([(21, 19), (3, 19)])
        case .gear:
            // The corrected canvas draws a toothed gear too (the user's decision over the old «sun» icon): its exact
            // polygon — 8 teeth, root radius 7.4, tip radius 9.6 — and a hole of radius 3.
            let pts: [(CGFloat, CGFloat)] = [
                (12.00, 4.60), (13.87, 2.58), (15.67, 3.13), (16.11, 5.85), (17.23, 6.77), (19.98, 6.67), (20.87, 8.33), (19.26, 10.56),
                (19.40, 12.00), (21.42, 13.87), (20.87, 15.67), (18.15, 16.11), (17.23, 17.23), (17.33, 19.98), (15.67, 20.87), (13.44, 19.26),
                (12.00, 19.40), (10.13, 21.42), (8.33, 20.87), (7.89, 18.15), (6.77, 17.23), (4.02, 17.33), (3.13, 15.67), (4.74, 13.44),
                (4.60, 12.00), (2.58, 10.13), (3.13, 8.33), (5.85, 7.89), (6.77, 6.77), (6.67, 4.02), (8.33, 3.13), (10.56, 4.74),
            ]
            line(pts, close: true)
            path.addEllipse(in: CGRect(x: ox + 9 * s, y: oy + 9 * s, width: 6 * s, height: 6 * s))
        case .mic, .micOff:
            path.addRoundedRect(in: CGRect(x: ox + 9 * s, y: oy + 3 * s, width: 6 * s, height: 11 * s), cornerSize: CGSize(width: 3 * s, height: 3 * s))
            path.move(to: p(6, 11)); arc(cx: 12, cy: 11, r: 6, from: 180, to: 0, clockwise: true)
            line([(12, 17), (12, 21)])
            if icon == .micOff { line([(4, 4), (20, 20)]) }
        case .waveform:
            line([(3, 12), (6, 12), (8.5, 6), (12.5, 18), (15, 10), (16.5, 12), (21, 12)])
        case .chevronDown: line([(7, 9.5), (12, 14.5), (17, 9.5)])
        case .chevronRight: line([(9.5, 6), (15.5, 12), (9.5, 18)])
        case .chevronLeft: line([(14.5, 6), (8.5, 12), (14.5, 18)])
        case .plus: line([(12, 5), (12, 19)]); line([(5, 12), (19, 12)])
        case .minus: line([(5, 12), (19, 12)])
        case .play: line([(8, 5.5), (8, 18.5), (18.5, 12)], close: true)
        case .stop: path.addRoundedRect(in: CGRect(x: ox + 6.5 * s, y: oy + 6.5 * s, width: 11 * s, height: 11 * s), cornerSize: CGSize(width: 2.5 * s, height: 2.5 * s))
        case .repeatArrows:
            line([(4, 11), (4, 9), (7, 6), (18, 6)]); line([(15, 3), (18, 6), (15, 9)])
            line([(20, 13), (20, 15), (17, 18), (6, 18)]); line([(9, 21), (6, 18), (9, 15)])
        case .lock:
            path.addRoundedRect(in: CGRect(x: ox + 5.5 * s, y: oy + 11 * s, width: 13 * s, height: 9 * s), cornerSize: CGSize(width: 2 * s, height: 2 * s))
            path.move(to: p(8.5, 11)); path.addLine(to: p(8.5, 8)); arc(cx: 12, cy: 8, r: 3.5, from: 180, to: 360, clockwise: false); path.addLine(to: p(15.5, 11))
        case .route:
            // Path along the neck: three dots joined by a zigzag.
            line([(5, 18), (12, 12), (12, 12), (19, 6)])
            path.addEllipse(in: CGRect(x: ox + 3 * s, y: oy + 16 * s, width: 4 * s, height: 4 * s))
            path.addEllipse(in: CGRect(x: ox + 10 * s, y: oy + 10 * s, width: 4 * s, height: 4 * s))
            path.addEllipse(in: CGRect(x: ox + 17 * s, y: oy + 4 * s, width: 4 * s, height: 4 * s))
        case .bluetooth:
            line([(7, 7.5), (17, 16.5), (12, 21), (12, 3), (17, 7.5), (7, 16.5)])
        case .music:
            line([(9, 18), (9, 6), (19, 4), (19, 16)])
            path.addEllipse(in: CGRect(x: ox + 4.8 * s, y: oy + 15.8 * s, width: 4.4 * s, height: 4.4 * s))
            path.addEllipse(in: CGRect(x: ox + 14.8 * s, y: oy + 13.8 * s, width: 4.4 * s, height: 4.4 * s))
        case .search:
            path.addEllipse(in: CGRect(x: ox + 4.5 * s, y: oy + 4.5 * s, width: 13 * s, height: 13 * s))
            line([(16, 16), (20.5, 20.5)])
        case .pause:
            path.addRoundedRect(in: CGRect(x: ox + 7 * s, y: oy + 5.5 * s, width: 3.5 * s, height: 13 * s), cornerSize: CGSize(width: s, height: s))
            path.addRoundedRect(in: CGRect(x: ox + 13.5 * s, y: oy + 5.5 * s, width: 3.5 * s, height: 13 * s), cornerSize: CGSize(width: s, height: s))
        case .close: line([(6.5, 6.5), (17.5, 17.5)]); line([(17.5, 6.5), (6.5, 17.5)])
        case .strobe:
            // Ring of 8 dashes around a dot: the strobe disc.
            for i in 0..<8 {
                let a = Double(i) * .pi / 4
                line([(12 + 6 * CGFloat(cos(a)), 12 + 6 * CGFloat(sin(a))), (12 + 9.5 * CGFloat(cos(a)), 12 + 9.5 * CGFloat(sin(a)))])
            }
            path.addEllipse(in: CGRect(x: ox + 10.5 * s, y: oy + 10.5 * s, width: 3 * s, height: 3 * s))
        case .expand:
            line([(4, 9), (4, 4), (9, 4)]); line([(15, 4), (20, 4), (20, 9)])
            line([(20, 15), (20, 20), (15, 20)]); line([(9, 20), (4, 20), (4, 15)])
        case .timer:
            path.addEllipse(in: CGRect(x: ox + 4.5 * s, y: oy + 5.5 * s, width: 15 * s, height: 15 * s))
            line([(12, 9), (12, 13), (14.5, 15)]); line([(10, 3), (14, 3)])
        case .arrowUp: line([(12, 19), (12, 5)]); line([(6, 11), (12, 5), (18, 11)])
        case .warning:
            line([(12, 4), (21, 20), (3, 20)], close: true)
            line([(12, 10), (12, 14.5)]); line([(12, 17.2), (12, 17.5)])
        case .refresh:
            path.move(to: p(19, 12)); arc(cx: 12, cy: 12, r: 7, from: 0, to: 314.4, clockwise: false)
            line([(19, 4.5), (19, 8.5), (15, 8.5)])
        case .trash:
            line([(5, 7), (19, 7)]); line([(10, 7), (10, 5), (14, 5), (14, 7)]); line([(7, 7), (8, 19), (16, 19), (17, 7)])
        case .rename:
            for y in [7.0, 12, 17] { line([(5, y), (19, y)]) }
            path.addEllipse(in: CGRect(x: ox + 7 * s, y: oy + 5 * s, width: 4 * s, height: 4 * s))
        case .check: line([(5, 12.5), (9.5, 17), (19, 7.5)])
        case .list: for y in [7.0, 12, 17] { line([(5, y), (19, y)]) }
        case .audioInterface:
            path.addRoundedRect(in: CGRect(x: ox + 3.5 * s, y: oy + 7 * s, width: 17 * s, height: 10 * s), cornerSize: CGSize(width: 2 * s, height: 2 * s))
            path.addEllipse(in: CGRect(x: ox + 6 * s, y: oy + 10 * s, width: 4 * s, height: 4 * s))
        case .sliders:
            line([(4, 8), (20, 8)]); line([(4, 16), (20, 16)])
            path.addEllipse(in: CGRect(x: ox + 7 * s, y: oy + 6 * s, width: 4 * s, height: 4 * s))
            path.addEllipse(in: CGRect(x: ox + 13 * s, y: oy + 14 * s, width: 4 * s, height: 4 * s))
        }
        return path
    }
}

struct Icon: View {
    let icon: AppIcon
    var size: CGFloat = 24
    var lineWidth: CGFloat = 1.6
    var color: Color = Theme.textBody

    init(_ icon: AppIcon, size: CGFloat = 24, lineWidth: CGFloat = 1.6, color: Color = Theme.textBody) {
        self.icon = icon
        self.size = size
        self.lineWidth = lineWidth
        self.color = color
    }

    var body: some View {
        Group {
            if icon.filled {
                IconShape(icon: icon).fill(color)
            } else {
                IconShape(icon: icon).stroke(color, style: StrokeStyle(lineWidth: lineWidth * size / 24, lineCap: .round, lineJoin: .round))
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}
