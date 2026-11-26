import SwiftUI

/// Tempo knob of the canvas (290 pt): a 270° scale with minor ticks every 3° and majors every 27°, the progress arc
/// from 20 to 400 BPM, a knurled ring, a brushed-metal ring with a pointer, and a dark face with the tempo.
/// Every size is the canvas size × `size / 290`.
struct TempoKnob: View {
    let bpm: Double
    var size: CGFloat = 290
    var dimmed = false
    var caption = "BPM · свайп по ручке"
    let onDrag: (Double) -> Void
    let onDoubleTap: () -> Void

    @State private var lastPoint: CGPoint?
    @State private var accumulated: Double = 0

    private var fraction: Double { ((bpm - 20) / 380).clamped(to: 0...1) }

    var body: some View {
        let k = size / 290
        ZStack {
            scale(k)
            knob(k)
        }
        .frame(width: size, height: size)
        .contentShape(Circle())
        .gesture(rotation(k))
        .onTapGesture(count: 2, perform: onDoubleTap)
        .accessibilityElement()
        .accessibilityLabel("Темп")
        .accessibilityValue("\(Int(bpm)) ударов в минуту")
        .accessibilityAdjustableAction { direction in
            onDrag(direction == .increment ? 1 : -1)
        }
        // A11Y-3: big steps too.
        .accessibilityAction(named: "Быстрее на 10") { onDrag(10) }
        .accessibilityAction(named: "Медленнее на 10") { onDrag(-10) }
    }

    // MARK: Scale (svg 290 × 290, arc r 138, pathLength 270)

    private func arc(_ k: CGFloat, to degrees: Double = 270) -> Path {
        var p = Path()
        p.addArc(center: CGPoint(x: 145 * k, y: 145 * k), radius: 138 * k,
                 startAngle: .degrees(135), endAngle: .degrees(135 + degrees), clockwise: false)
        return p
    }

    private func scale(_ k: CGFloat) -> some View {
        // pathLength 270 → one dash unit is one degree of the arc.
        let unit = 138 * k * .pi / 180
        return ZStack {
            arc(k).stroke(Color(hex: 0xe9e6df, opacity: 0.22), style: StrokeStyle(lineWidth: 8 * k, dash: [0.5 * unit, 2.5 * unit]))
            arc(k).stroke(Color(hex: 0xe9e6df, opacity: 0.6), style: StrokeStyle(lineWidth: 12 * k, dash: [0.8 * unit, 26.2 * unit]))
            if fraction > 0 {
                arc(k, to: 270 * fraction)
                    .stroke(Theme.beat, style: StrokeStyle(lineWidth: 3 * k, lineCap: .round))
                    .opacity(dimmed ? 0.45 : 1)
            }
        }
        .frame(width: 290 * k, height: 290 * k)
    }

    // MARK: Knob (240 at 25; metal 222 at 9; face 164 at 38)

    private static let knurl: AngularGradient = {
        var stops: [Gradient.Stop] = []
        for i in 0..<72 {
            let a = Double(i) * 5 / 360, b = (Double(i) * 5 + 2.5) / 360, c = (Double(i) * 5 + 5) / 360
            stops += [.init(color: Color(hex: 0x33363b), location: a), .init(color: Color(hex: 0x33363b), location: b),
                      .init(color: Color(hex: 0x4f5359), location: b), .init(color: Color(hex: 0x4f5359), location: c)]
        }
        return AngularGradient(stops: stops, center: .center, angle: .degrees(-90))
    }()

    private func knob(_ k: CGFloat) -> some View {
        ZStack {
            Circle().fill(Self.knurl)
                .frame(width: 240 * k, height: 240 * k)
                .overlay(Circle().strokeBorder(Color.black.opacity(0.8), lineWidth: 1 * k).padding(-1 * k))
                .shadow(color: .black.opacity(0.9), radius: 35 * k, y: 34 * k)
            Circle().fill(Theme.metal)
                .frame(width: 222 * k, height: 222 * k)
                .overlay(
                    Circle().strokeBorder(Color.white.opacity(0.75), lineWidth: 1 * k)
                        .offset(y: 1 * k).blur(radius: 0.5 * k)
                        .mask(Circle())
                )
            // Face rings: 0 0 0 3px rgba(255,255,255,.35) under 0 0 0 2px #2a2c30.
            Circle().fill(Color.white.opacity(0.35)).frame(width: 170 * k, height: 170 * k)
            Circle().fill(Color(hex: 0x2a2c30)).frame(width: 168 * k, height: 168 * k)
            face(k)
            // Pointer: 4 × 18, r 2, 13 pt from the knurl's top, turning about the knob centre.
            RoundedRectangle(cornerRadius: 2 * k)
                .fill(Color(hex: 0x1a1b1e))
                .frame(width: 4 * k, height: 18 * k)
                .offset(y: -(120 - 13 - 9) * k)
                .rotationEffect(.degrees(-135 + 270 * fraction))
        }
        .frame(width: 290 * k, height: 290 * k)
    }

    private func face(_ k: CGFloat) -> some View {
        Circle()
            .fill(RadialGradient(colors: [Theme.faceTop, Color(hex: 0x0b0b0c)], center: UnitPoint(x: 0.5, y: 0.38),
                                 startRadius: 0, endRadius: 91.4 * k))
            .overlay(
                Circle().stroke(Color.black.opacity(0.95), lineWidth: 12 * k)
                    .blur(radius: 7 * k).offset(y: 5 * k)
                    .mask(Circle())
            )
            .frame(width: 164 * k, height: 164 * k)
            .overlay {
                VStack(spacing: 0) {
                    Text("\(Int(bpm))")
                        .font(Typo.fixed(70 * k, .extraLight))
                        .kerning(-0.04 * 70 * k)
                        .foregroundStyle(Theme.textPrimary)
                        .monospacedDigit()
                        .opacity(dimmed ? 0.45 : 1)
                        .frame(height: 63 * k)
                        .contentTransition(.identity)
                    Text(caption).font(Typo.fixed(12 * k)).foregroundStyle(Theme.textTertiary)
                        .padding(.top, 6 * k)
                }
            }
    }

    // MARK: Gesture

    /// «Свайп по ручке» (canvas, PRD 6.2.6): up or right is faster, down or left is slower, 4 pt per BPM, anywhere on
    /// the knob. It was an angle around the centre: a swipe through the middle flipped the angle and threw the tempo to
    /// 20, and on the right half an upward swipe slowed it down (UX check on the iPhone).
    private func rotation(_ k: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 8)     // a light touch no longer moves the tempo
            .onChanged { value in
                if let last = lastPoint {
                    // Fast swipes go further (20 → 400 took five swipes); slow ones stay precise.
                    let move = Double((value.location.x - last.x) - (value.location.y - last.y))
                    accumulated += move / 4 * (abs(move) > 12 ? 2 : 1)
                    let whole = accumulated.rounded(.towardZero)
                    if whole != 0 {
                        accumulated -= whole
                        onDrag(whole)
                    }
                }
                lastPoint = value.location
            }
            .onEnded { _ in lastPoint = nil; accumulated = 0 }
    }
}
