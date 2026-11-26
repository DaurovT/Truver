import SwiftUI

/// The Truver mark (canvas «Бренд»): a needle standing on the green mark — the moment «в строю». Rim, 24 ticks,
/// 22 green segments (9° every 15°) with a 36° gap at the top where the needle stands. No needle hub on purpose:
/// otherwise it reads as a clock.
struct BrandMark: View {
    /// One colour for the whole mark (empty states); nil = ivory and green.
    var tint: Color?

    var body: some View {
        let ink = tint ?? Theme.textPrimary
        let green = tint ?? Theme.inTune
        Canvas { context, size in
            let k = min(size.width, size.height) / 100
            let c = CGPoint(x: size.width / 2, y: size.height / 2)
            func arc(radius: Double, from: Double, to: Double) -> Path {
                var p = Path()
                p.addArc(center: c, radius: radius * k, startAngle: .degrees(from), endAngle: .degrees(to), clockwise: false)
                return p
            }
            context.stroke(Path(ellipseIn: CGRect(x: c.x - 45 * k, y: c.y - 45 * k, width: 90 * k, height: 90 * k)),
                           with: .color(ink), lineWidth: 3.2 * k)
            for i in 0..<24 {
                let mid = -90.0 + Double(i) * 15
                context.stroke(arc(radius: 40, from: mid - 0.45, to: mid + 0.45), with: .color(ink.opacity(tint == nil ? 0.5 : 1)), lineWidth: 4 * k)
            }
            for i in 0..<22 {
                let start = -72.0 + Double(i) * 15
                context.stroke(arc(radius: 29, from: start, to: start + 9), with: .color(green.opacity(0.95)), lineWidth: 5.5 * k)
            }
            var marker = Path()
            marker.move(to: CGPoint(x: c.x, y: c.y + (13.5 - 50) * k))
            marker.addLine(to: CGPoint(x: c.x - 5.5 * k, y: c.y + (3.5 - 50) * k))
            marker.addLine(to: CGPoint(x: c.x + 5.5 * k, y: c.y + (3.5 - 50) * k))
            marker.closeSubpath()
            context.fill(marker, with: .color(green))
            context.fill(Path(roundedRect: CGRect(x: c.x - 2.4 * k, y: c.y + (13 - 50) * k, width: 4.8 * k, height: 16 * k),
                              cornerRadius: 2.4 * k), with: .color(green))
        }
        .accessibilityLabel("Знак Truver")
    }
}

/// Word mark: "truver" in Inter Light with a small green triangle above the "v".
struct Wordmark: View {
    var size: CGFloat = 64

    var body: some View {
        HStack(spacing: 0) {
            Text("tru")
            Text("v").overlay(alignment: .top) {
                Triangle().fill(Theme.inTune)
                    .frame(width: size * 0.17, height: size * 0.13)
                    // CSS: top −0.06 em of the inline «v» box, whose top is the text frame top (measured on the corrected canvas).
                    .offset(y: size * -0.06)
            }
            Text("er")
        }
        .font(Typo.inter(size, .light))
        .kerning(-0.035 * size)
        .foregroundStyle(Theme.textPrimary)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Truver")
    }
}

struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        p.closeSubpath()
        return p
    }
}

/// Small metal bezel with a dark face (onboarding microphone step).
struct MiniBezel<Content: View>: View {
    var size: CGFloat = 200
    @ViewBuilder var content: () -> Content

    var body: some View {
        ZStack {
            Circle().fill(Theme.metal).shadow(color: .black.opacity(0.8), radius: 30, y: 30)
            Circle().fill(RadialGradient(colors: [Theme.faceTop, Color(hex: 0x0b0b0c)], center: UnitPoint(x: 0.5, y: 0.38),
                                         startRadius: 0, endRadius: size * 0.45))
                .padding(size * 0.1)
            content()
        }
        .frame(width: size, height: size)
    }
}
