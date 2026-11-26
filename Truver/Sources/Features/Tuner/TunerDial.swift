import SwiftUI
import TruverDSP
import TruverTheory

/// What the centre of the dial shows (one per tuner state of the canvas).
enum DialCenter: Equatable {
    /// `dimmed`: the waiting state keeps the target note at 25 % (canvas «Ожидание»).
    case note(name: String, octave: String, cents: String, centsColor: Color, detail: String, dimmed: Bool = false)
    /// TU-10 strobe view (canvas «Тюнер — строб»): a lighter 64 pt note with the octave inline and one line.
    case strobeNote(name: String, octave: String, line: String, color: Color)
    /// Round badge (54 pt + 1 pt border), 17 semibold title, 12 pt explanation.
    case message(icon: AppIcon?, iconColor: Color, title: String, detail: String?)
    case listening
    case done(detail: String)
    case reference(title: String, detail: String)
}

/// The tuner instrument (canvas «Тюнер», 2026-11 «Fix» boards): brushed-metal bezel, knurled ring, dark face with
/// the scale and the green top marker, the deviation needle on the scale (1.2° per cent, ±50 c = ±60°), and an
/// inner strobe band in the deviation colour that turns with the deviation (6 °/s per cent, still within ±1 c).
struct TunerDial: View {
    let center: DialCenter
    /// Needle deviation in cents; nil = no needle.
    var needle: Double? = nil
    /// Deviation colour of the needle and the band; nil = idle band (white 8 %).
    var color: Color? = nil
    /// Deviation that turns the band; nil = still.
    var bandCents: Double? = nil
    var glow = false
    /// TU-10 strobe view: the band stands at the signal phase (turns as the string drifts).
    var phase: Double? = nil
    var strobeView = false
    /// «Эталон»: the remaining part of the 3 s countdown as a light ring over the band.
    var progress: Double? = nil
    /// Live countdown: the ring shrinks until this moment (3 s of the reference tone).
    var countdownUntil: Date? = nil
    /// Screenshots (`-tunerDemo`): every animation stands at its first frame, as on the canvas render.
    var frozen = false
    /// Band angle of a frozen screenshot (the canvas render catches the band 0.05 s into its spin).
    var bandAngle: Double = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var strobe = StrobeBox()
    @State private var follower = SpringFollower()

    var body: some View {
        GeometryReader { geo in
            let size = min(geo.size.width, geo.size.height)
            let s = size / 320
            ZStack {
                // Bezel
                Circle().fill(Theme.metal)
                    .overlay(Circle().stroke(Color.white.opacity(0.6), lineWidth: 0.5).blur(radius: 0.3).offset(y: 0.5).mask(Circle()))
                    .shadow(color: .black.opacity(0.85), radius: 40 * s, y: 40 * s)
                // Knurl
                KnurlRing().opacity(0.6).padding(8 * s)
                // Face glow (canvas `glowpulse`: 0 0 28px 4px green 35 % at the middle of a 2.4 s breath).
                if glow { faceGlow(s) }
                // Face
                Circle()
                    .fill(RadialGradient(colors: [Theme.faceTop, Color(hex: 0x0b0b0c), Theme.faceBottom],
                                         center: UnitPoint(x: 0.5, y: 0.4), startRadius: 0, endRadius: 150 * s))
                    .overlay(Circle().stroke(Color(hex: 0x2a2c30), lineWidth: 2 * s))
                    .overlay(Circle().stroke(Color.black.opacity(0.95), lineWidth: 10 * s).blur(radius: 9 * s).offset(y: 6 * s).mask(Circle()))
                    .padding(13 * s)
                DialScale().padding(13 * s)
                if let needle, let color { needleView(needle, color: color, s: s) }
                strobeBand(s)
                if let progress { ring(progress, s: s) }
                if let countdownUntil {
                    TimelineView(.animation) { t in ring(countdownUntil.timeIntervalSince(t.date) / 3, s: s) }
                }
                Circle().stroke(Color.white.opacity(0.07), lineWidth: 1).frame(width: 188 * s, height: 188 * s)
                content(s)
                    .frame(width: 184 * s, height: 184 * s)
            }
            .frame(width: size, height: size)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .aspectRatio(1, contentMode: .fit)
    }

    /// Canvas `progress`: a full ivory ring over the band (r 105, 8 pt) whose dash runs out from the top.
    private func ring(_ value: Double, s: CGFloat) -> some View {
        Circle().trim(from: 0, to: max(0, min(1, value)))
            .stroke(Theme.beat, style: StrokeStyle(lineWidth: 8 * s))
            .rotationEffect(.degrees(-90))
            .frame(width: 210 * s, height: 210 * s)
    }

    @ViewBuilder private func faceGlow(_ s: CGFloat) -> some View {
        let halo = { (a: Double) in
            Circle().fill(Theme.inTune.opacity(a)).padding(9 * s).blur(radius: 14 * s)
        }
        if frozen || reduceMotion {
            halo(frozen ? 0 : 0.35)
        } else {
            TimelineView(.animation) { t in
                let p = t.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 2.4) / 2.4
                halo(0.35 * (1 - cos(2 * .pi * p)) / 2)
            }
        }
    }

    /// Canvas: a 4 × 15 bar (radius 2) at the top of the face, 7 pt from its edge, glowing 5 pt in its colour.
    @ViewBuilder private func needleView(_ cents: Double, color: Color, s: CGFloat) -> some View {
        let bar = { (value: Double) in
            RoundedRectangle(cornerRadius: 2 * s).fill(color)
                .frame(width: 4 * s, height: 15 * s)
                .shadow(color: color, radius: 2.5 * s)
                .position(x: 147 * s, y: 14.5 * s)
                .frame(width: 294 * s, height: 294 * s)
                .rotationEffect(.degrees(1.2 * max(-50, min(50, value))))
        }
        if frozen {
            bar(cents)
        } else {
            TimelineView(.animation) { t in
                bar(follower.step(to: max(-50, min(50, cents)), at: t.date, reduceMotion: reduceMotion))
            }
        }
    }

    @ViewBuilder private func strobeBand(_ s: CGFloat) -> some View {
        let band = Circle()
            .stroke(color.map { $0.opacity(0.9) } ?? Color.white.opacity(0.08),
                    style: StrokeStyle(lineWidth: 8 * s, dash: [2.5 * s, 5.5 * s]))
            .frame(width: 210 * s, height: 210 * s)
        if frozen {
            band.rotationEffect(.degrees(bandAngle))
        } else if reduceMotion {
            band
        } else if strobeView {
            band.rotationEffect(.degrees(phase ?? 0))
        } else if let bandCents {
            TimelineView(.animation) { timeline in
                band.rotationEffect(.degrees(strobe.angle(cents: bandCents, at: timeline.date)))
            }
        } else {
            band
        }
    }

    /// Centre column of the canvas (184 × 184, flex column centred). Instrument text: fixed sizes (the large-text
    /// canvas keeps the dial at 96 / 22 / 12), Inter with system ♯ ♭ (`Typo.notes`).
    @ViewBuilder private func content(_ s: CGFloat) -> some View {
        switch center {
        case let .note(name, octave, cents, color, detail, dimmed):
            VStack(spacing: 0) {
                noteName(name, octave: octave, s: s)
                    .opacity(dimmed ? 0.25 : 1)
                // Empty lines keep their min-height (26 / 15), so the waiting note sits where the reading's does.
                Typo.notes(cents, size: 22 * s, weight: .medium, fixed: true).foregroundStyle(color)
                    .lineLimit(1)
                    .frame(minHeight: 26 * s)
                    .padding(.top, 6 * s)
                    .contentTransition(.identity)
                Typo.notes(detail, size: 12 * s, fixed: true).foregroundStyle(Theme.textTertiary)
                    .lineLimit(1).minimumScaleFactor(0.7)
                    .frame(minHeight: 15 * s)
                    .padding(.top, 4 * s)
            }
        case let .strobeNote(name, octave, line, color):
            VStack(spacing: 6 * s) {
                // line-height 1: a 64 pt box; the octave is an inline 20 pt span on the same baseline.
                (Typo.notes(name, size: 64 * s, weight: .extraLight, fixed: true).foregroundColor(Theme.textPrimary)
                    + Text(octave).font(Typo.fixed(20 * s)).foregroundColor(Theme.textSecondary))
                    .lineLimit(1)
                    .fixedSize()
                    .frame(height: 64 * s)
                Typo.notes(line, size: 13 * s, fixed: true).foregroundStyle(color)
                    .lineLimit(1).minimumScaleFactor(0.7)
            }
        case let .message(icon, iconColor, title, detail):
            VStack(spacing: 0) {
                if let icon {
                    badge(border: Color.white.opacity(0.12), s: s) { Icon(icon, size: 24 * s, color: iconColor) }
                }
                Text(title).font(Typo.fixed(17 * s, .semibold)).foregroundStyle(Theme.textPrimary).multilineTextAlignment(.center)
                    .frame(maxWidth: 168 * s)
                    .padding(.top, icon == nil ? 0 : 12 * s)
                if let detail { explanation(detail, s: s) }
            }
        case .listening:
            VStack(spacing: 0) {
                SoundBars(heights: [10, 18, 28, 20, 12, 8], color: Theme.textSecondary.opacity(0.7), animated: false, scale: s)
                Text("Слушаю…").font(Typo.fixed(17 * s, .semibold)).foregroundStyle(Theme.textPrimary)
                    .padding(.top, 12 * s)
                Text("звук есть, нота ещё не ясна").font(Typo.fixed(12 * s)).foregroundStyle(Theme.textSecondary)
                    .padding(.top, 4 * s)
            }
        case let .done(detail):
            VStack(spacing: 0) {
                badge(border: Theme.inTune.opacity(0.6), s: s) { Icon(.check, size: 26 * s, lineWidth: 2.2, color: Theme.inTune) }
                Text("Готово").font(Typo.fixed(17 * s, .semibold)).foregroundStyle(Theme.textPrimary)
                    .padding(.top, 12 * s)
                explanation(detail, s: s)
            }
            .transition(.scale(scale: 0.6).combined(with: .opacity))
        case let .reference(title, detail):
            VStack(spacing: 0) {
                SoundBars(heights: [18, 30, 40, 34, 24, 14], color: Theme.textPrimary, animated: !frozen, scale: s)
                Typo.notes(title, size: 17 * s, weight: .semibold, fixed: true).foregroundStyle(Theme.textPrimary)
                    .padding(.top, 12 * s)
                Typo.notes(detail, size: 12 * s, fixed: true).foregroundStyle(Theme.textSecondary)
                    .padding(.top, 4 * s)
            }
        }
    }

    /// Canvas: a 54 pt disc (white 4 %) with a 1 pt border outside it — 56 pt in all.
    private func badge(border: Color, s: CGFloat, @ViewBuilder icon: () -> some View) -> some View {
        icon()
            .frame(width: 56 * s, height: 56 * s)
            .background(Circle().fill(Color.white.opacity(0.04)))
            .overlay(Circle().strokeBorder(border, lineWidth: 1))
    }

    /// 12 pt, line-height 1.35 (1.67 pt between lines, half of it above the first and below the last), 160 wide.
    private func explanation(_ text: String, s: CGFloat) -> some View {
        Text(text).font(Typo.fixed(12 * s)).foregroundStyle(Theme.textSecondary).multilineTextAlignment(.center)
            .lineSpacing(1.67 * s)
            .padding(.vertical, 0.83 * s)
            .frame(maxWidth: 160 * s)
            .padding(.top, 4 * s)
    }

    /// Canvas: the note 96 Light, letter-spacing −0.02 em, line-height 1 (a 96 pt box); the octave 22 Regular hangs
    /// off the note's right edge (+3 pt) with its 22 pt line box 12 pt above the box bottom — its baseline 1.9 pt
    /// above the note's. Only the letter is centred; the octave does not push it left.
    private func noteName(_ name: String, octave: String, s: CGFloat) -> some View {
        // 5.1.4: 96 pt for 1–2 characters, 72 for 3–4, 60 for «соль♯» (canvas «Обозначения — сольфеджио»).
        let size = CGFloat(NoteFormatter.dialSize(for: name))
        return Typo.notes(name, size: size * s, weight: .light, fixed: true)
            .tracking(-0.02 * size * s)
            .foregroundStyle(Theme.textPrimary)
            .lineLimit(1).minimumScaleFactor(0.5)
            // Natural line height (116 pt): proposed only the 96 pt box, the text would shrink to 82 %.
            .fixedSize(horizontal: false, vertical: true)
            .overlay(alignment: Alignment(horizontal: .trailing, vertical: .lastTextBaseline)) {
                Text(octave).font(Typo.fixed(22 * s)).foregroundStyle(Theme.textSecondary)
                    .fixedSize()
                    .alignmentGuide(.trailing) { $0[.leading] - 3 * s }
                    .alignmentGuide(.lastTextBaseline) { $0[.lastTextBaseline] + 1.9 * s }
            }
            .frame(height: 96 * s)
    }
}

/// «Слушаю» / «Эталон» (canvas): six 5 pt bars (radius 3), 4 apart, centred in a 40 pt row. The reference bars
/// breathe (`wave`: scaleY 0.35 ↔ 1 in 0.9 s, 0.1 s apart); still bars — at the first frame (0.35) for the
/// reference, at full height for «Слушаю».
struct SoundBars: View {
    let heights: [CGFloat]
    let color: Color
    let animated: Bool
    let scale: CGFloat
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            if animated && !reduceMotion {
                TimelineView(.animation) { timeline in bars(at: timeline.date.timeIntervalSinceReferenceDate) }
            } else {
                bars(at: nil)
            }
        }
        .frame(height: 40 * scale)
        .accessibilityHidden(true)
    }

    private func bars(at t: TimeInterval?) -> some View {
        HStack(spacing: 4 * scale) {
            ForEach(Array(heights.enumerated()), id: \.offset) { i, h in
                let y: CGFloat = {
                    guard animated else { return 1 }
                    guard let t else { return 0.35 }
                    let phase = ((t - Double(i) * 0.1) / 0.9).truncatingRemainder(dividingBy: 1)
                    return 0.35 + 0.65 * (1 - cos(2 * .pi * phase)) / 2
                }()
                RoundedRectangle(cornerRadius: 3 * scale).fill(color)
                    .frame(width: 5 * scale, height: h * scale)
                    .scaleEffect(x: 1, y: y)
            }
        }
    }
}

/// Accumulates the strobe band angle between frames (core `StrobeRotation`).
final class StrobeBox {
    private var rotation = StrobeRotation()
    private var last: Date?

    func angle(cents: Double, at time: Date) -> Double {
        let dt = last.map { min(0.1, time.timeIntervalSince($0)) } ?? 0
        last = time
        return rotation.advance(cents: cents, dt: dt)
    }
}

/// Fine knurl around the face: alternating 1° dark and light segments.
struct KnurlRing: View {
    var body: some View {
        Canvas { context, size in
            let c = CGPoint(x: size.width / 2, y: size.height / 2)
            let r = min(size.width, size.height) / 2
            for i in 0..<360 {
                var wedge = Path()
                wedge.move(to: c)
                wedge.addArc(center: c, radius: r, startAngle: .degrees(Double(i)), endAngle: .degrees(Double(i) + 1.05), clockwise: false)
                wedge.closeSubpath()
                context.fill(wedge, with: .color(i % 2 == 0 ? Color.black.opacity(0.18) : Color.white.opacity(0.08)))
            }
        }
        .drawingGroup()
        .accessibilityHidden(true)
    }
}

/// Scale of the face: 120 fine ticks, 12 major ticks and the green top marker.
struct DialScale: View {
    var body: some View {
        Canvas { context, size in
            let s = size.width / 294
            let c = CGPoint(x: size.width / 2, y: size.height / 2)
            func tick(_ degrees: Double, length: Double, width: CGFloat, color: Color) {
                var path = Path()
                path.addArc(center: c, radius: 134 * s, startAngle: .degrees(degrees - 90 - length / 2),
                            endAngle: .degrees(degrees - 90 + length / 2), clockwise: false)
                context.stroke(path, with: .color(color), lineWidth: width)
            }
            for i in 0..<120 { tick(Double(i) * 3, length: 0.5, width: 8 * s, color: Color(hex: 0xe9e6df, opacity: 0.24)) }
            for i in 0..<12 { tick(Double(i) * 30, length: 0.8, width: 12 * s, color: Color(hex: 0xe9e6df, opacity: 0.65)) }
            var marker = Path()
            marker.move(to: CGPoint(x: 147 * s, y: 7 * s))
            marker.addLine(to: CGPoint(x: 142.5 * s, y: 1 * s))
            marker.addLine(to: CGPoint(x: 151.5 * s, y: 1 * s))
            marker.closeSubpath()
            context.fill(marker, with: .color(Theme.inTune))
        }
        .accessibilityHidden(true)
    }
}

/// TU-10 strobe strips (canvas «Тюнер — строб»): three 10 pt bars, 4 apart — stripes of 10 / 20 / 40 pt at
/// 85 / 60 / 40 % with equal gaps; they run with the signal phase (one full stripe period per turn) and stand
/// still in tune.
struct StrobeStrips: View {
    let phase: Double
    var body: some View {
        VStack(spacing: 4) {
            strip(10, opacity: 0.85)
            strip(20, opacity: 0.6)
            strip(40, opacity: 0.4)
        }
        .accessibilityHidden(true)
    }

    private func strip(_ width: CGFloat, opacity: Double) -> some View {
        Canvas { context, size in
            let period = width * 2
            var shift = CGFloat(phase / 360).truncatingRemainder(dividingBy: 1) * period
            if shift > 0 { shift -= period }
            var x = shift
            while x < size.width {
                context.fill(Path(CGRect(x: x, y: 0, width: width, height: size.height)), with: .color(Theme.textPrimary.opacity(opacity)))
                context.fill(Path(CGRect(x: x + width, y: 0, width: width, height: size.height)), with: .color(Color.white.opacity(0.03)))
                x += period
            }
        }
        .frame(height: 10)
        .clipShape(RoundedRectangle(cornerRadius: 5))
    }
}
