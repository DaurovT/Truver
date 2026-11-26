import SwiftUI

/// Colours of the «Спасибо · обновления» page (canvas): the gold of thanks and of the update banner.
enum ThanksColors {
    static let gold = Color(hex: 0xe8b54a)
    static let goldTop = Color(hex: 0xf3cf7a)
    static let goldBottom = Color(hex: 0xc98d22)
    static let ink = Color(hex: 0x16171a)
    static let badgeRing = Color(hex: 0x15161a)
    /// Initials avatars without a photo (canvas palette): top-left light, bottom-right dark.
    static let avatarPalette: [(UInt32, UInt32)] = [(0x6a5acd, 0x2c2650), (0x3f8f7a, 0x1b3a33), (0xb0624a, 0x4a2a20), (0x8a7a3a, 0x3a3418), (0x4a74b0, 0x1e2f4a)]
    static let partnerPalette: [(UInt32, UInt32)] = [(0x5b6470, 0x22262c), (0x7a5a3a, 0x2e2216), (0x6b3f5f, 0x2a1826), (0x3f6b6b, 0x182a2a)]
}

/// CSS `linear-gradient(<angle>deg, …)` over a box: the gradient line passes through the centre in the CSS direction
/// and is long enough to reach the corners.
func cssLinearGradient(_ degrees: Double, _ stops: [Gradient.Stop], aspect: CGFloat = 1) -> LinearGradient {
    let a = degrees * .pi / 180
    let dx = sin(a), dy = -cos(a)
    // In unit coordinates of a w × h box (aspect = w / h): half length of the gradient line.
    let half = (abs(dx) * aspect + abs(dy)) / 2
    let sx = dx * half / aspect, sy = dy * half
    return LinearGradient(stops: stops, startPoint: UnitPoint(x: 0.5 - sx, y: 0.5 - sy), endPoint: UnitPoint(x: 0.5 + sx, y: 0.5 + sy))
}

/// CSS `radial-gradient(120% 120% at 30% 20%, a, b)` of the avatars.
private func avatarGradient(_ colors: (UInt32, UInt32), size: CGFloat) -> some ShapeStyle {
    RadialGradient(colors: [Color(hex: colors.0), Color(hex: colors.1)], center: UnitPoint(x: 0.3, y: 0.2), startRadius: 0, endRadius: 1.2 * size)
}

// MARK: - Platform tiles

/// A platform tile (canvas «Плитки площадок»): the platform's colours, a white glyph, 1 pt inner border white 14 %.
/// Sizes 22 / 32 / 40 / 58 with radii 6 / 9 / 11 / 16 and glyphs 15 / 22 / 27 / 39.
struct PlatformTile: View {
    let kind: ThanksLink.Kind
    var size: CGFloat = 22
    var radius: CGFloat = 6
    var glyph: CGFloat = 15

    static func background(_ kind: ThanksLink.Kind) -> LinearGradient {
        func g(_ a: UInt32, _ b: UInt32) -> LinearGradient { cssLinearGradient(160, [.init(color: Color(hex: a), location: 0), .init(color: Color(hex: b), location: 1)]) }
        switch kind {
        case .youtube: return g(0xff4b42, 0xd7140f)
        case .instagram:
            return cssLinearGradient(45, [.init(color: Color(hex: 0xf7b13a), location: 0), .init(color: Color(hex: 0xe8423f), location: 0.4),
                                          .init(color: Color(hex: 0xc22f8f), location: 0.7), .init(color: Color(hex: 0x7b3fd1), location: 1)])
        case .tiktok: return g(0x222429, 0x0b0c0e)
        case .telegram: return g(0x37b9f5, 0x1d93d2)
        case .spotify: return g(0x2bd46a, 0x149a46)
        case .site: return g(0x6b7380, 0x3d434c)
        }
    }

    var body: some View {
        RoundedRectangle(cornerRadius: radius, style: .circular)
            .fill(Self.background(kind))
            .overlay(RoundedRectangle(cornerRadius: radius, style: .circular).strokeBorder(Color.white.opacity(0.14), lineWidth: 1))
            .overlay(PlatformGlyph(kind: kind).frame(width: glyph, height: glyph))
            .frame(width: size, height: size)
            .accessibilityLabel(ThanksLink(kind: kind, handle: "", url: "").platform)
    }
}

/// The white glyph of a platform on the 24 × 24 grid of the canvas.
struct PlatformGlyph: View {
    let kind: ThanksLink.Kind

    var body: some View {
        GeometryReader { proxy in
            let k = proxy.size.width / 24
            ZStack {
                switch kind {
                case .youtube:
                    SVGPath(data: "M9 7.2v9.6c0 .6.6.9 1.1.6l7.4-4.8c.5-.3.5-1 0-1.3L10.1 6.6C9.6 6.3 9 6.6 9 7.2z").fill(.white)
                case .instagram:
                    RoundedRectangle(cornerRadius: 6 * k, style: .circular).strokeBorder(.white, lineWidth: 2 * k)
                        .frame(width: 18 * k, height: 18 * k)   // rect 4…20 stroked 2 centred on the edge → 3…21
                    Circle().stroke(.white, lineWidth: 2 * k).frame(width: 7.2 * k, height: 7.2 * k)
                    Circle().fill(.white).frame(width: 2.4 * k, height: 2.4 * k).position(x: 16.9 * k, y: 7.1 * k)
                case .tiktok:
                    let note = "M13.5 4v10.2a3.3 3.3 0 1 1-2.6-3.2"
                    let style = StrokeStyle(lineWidth: 2.2 * k, lineCap: .round)
                    SVGPath(data: note).stroke(Color(hex: 0x25f4ee), style: style).offset(x: -0.8 * k, y: -0.6 * k)
                    SVGPath(data: note).stroke(Color(hex: 0xfe2c55), style: style).offset(x: 0.8 * k, y: 0.6 * k)
                    SVGPath(data: note + "M13.5 4c.4 2.3 2 3.8 4.3 4").stroke(.white, style: style)
                case .telegram:
                    SVGPath(data: "M4.5 11.4l13.6-5.3c.7-.3 1.3.2 1.1 1l-2.3 10.9c-.2.8-.8 1-1.4.6l-3.6-2.7-1.8 1.7c-.2.2-.4.3-.7.3l.3-3.7 6.6-6c.3-.3-.1-.4-.4-.2l-8.2 5.2-3.5-1.1c-.8-.2-.8-.8.3-1.2z").fill(.white)
                case .spotify:
                    SVGPath(data: "M6.5 9.3c3.8-1.2 8.1-.9 11 .8M7.2 12.6c3.1-.9 6.4-.6 8.9.7M7.9 15.7c2.4-.6 4.8-.4 6.7.6")
                        .stroke(Color(hex: 0x0b0c0e), style: StrokeStyle(lineWidth: 2 * k, lineCap: .round))
                case .site:
                    Circle().stroke(.white, lineWidth: 1.7 * k).frame(width: 16 * k, height: 16 * k)
                    SVGPath(data: "M4 12h16M12 4c2.4 2.4 2.4 13.6 0 16M12 4c-2.4 2.4-2.4 13.6 0 16").stroke(.white, lineWidth: 1.7 * k)
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .accessibilityHidden(true)
    }
}

// MARK: - The gold plectrum

/// The gold plectrum with a heart (canvas «Спасибо»): `viewBox 0 0 56 56`, gradient #f3cf7a → #c98d22 from the
/// top-left to the bottom-right of the pick, the heart #16171a.
struct ThanksPick: View {
    var size: CGFloat = 30
    static let outline = "M28 4C40 4 50 9 50 19c0 13-12 27-19.5 32.5a4.2 4.2 0 0 1-5 0C18 46 6 32 6 19 6 9 16 4 28 4z"
    static let heart = "M28 34.5s-9.5-5.6-9.5-12.2c0-3.1 2.3-5.3 5.1-5.3 2 0 3.5 1.1 4.4 2.6.9-1.5 2.4-2.6 4.4-2.6 2.8 0 5.1 2.2 5.1 5.3 0 6.6-9.5 12.2-9.5 12.2z"

    var body: some View {
        ZStack {
            // objectBoundingBox of the outline: x 6…50, y 4…~52.4 (of 56).
            SVGPath(data: Self.outline, viewBox: 56)
                .fill(LinearGradient(colors: [ThanksColors.goldTop, ThanksColors.goldBottom],
                                     startPoint: UnitPoint(x: 6 / 56, y: 4 / 56), endPoint: UnitPoint(x: 50 / 56, y: 52.4 / 56)))
            SVGPath(data: Self.heart, viewBox: 56).fill(ThanksColors.ink)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

// MARK: - Avatars

/// The gold badge on an avatar: a heart for musicians, the partner's kind for partners. Gold disc 19 / 22 / 26 pt in a
/// 2 pt dark ring outside it (CSS content-box: 23 / 26 / 30 in all), glyph 13 / 16 / 20.
struct ThanksBadge: View {
    var kind: ThanksPerson.PartnerKind?
    var size: CGFloat = 19
    var glyph: CGFloat = 13

    var body: some View {
        Circle()
            .fill(cssLinearGradient(160, [.init(color: ThanksColors.goldTop, location: 0), .init(color: ThanksColors.goldBottom, location: 1)]))
            .frame(width: size, height: size)
            .overlay(glyphView.frame(width: glyph, height: glyph))
            .padding(2)
            .background(Circle().fill(ThanksColors.badgeRing))
    }

    @ViewBuilder private var glyphView: some View {
        switch kind {
        case nil:
            SVGPath(data: "M12 3.5c3.6 0 6.5 1.5 6.5 4.4 0 3.9-3.6 8.4-5.7 10.4a1.2 1.2 0 0 1-1.6 0C9.1 16.3 5.5 11.8 5.5 7.9c0-2.9 2.9-4.4 6.5-4.4z").fill(ThanksColors.ink)
        case .school?:
            SVGPath(data: "M3 9.5L12 5l9 4.5-9 4.5z M7 11.6v3.6c0 1.3 2.2 2.6 5 2.6s5-1.3 5-2.6v-3.6")
                .stroke(ThanksColors.ink, style: StrokeStyle(lineWidth: 2 * glyph / 24, lineJoin: .round))
        case .shop?:
            SVGPath(data: "M6 8h12l-1 11H7z M9 8V6.5a3 3 0 0 1 6 0V8")
                .stroke(ThanksColors.ink, style: StrokeStyle(lineWidth: 2 * glyph / 24, lineJoin: .round))
        case .festival?:
            SVGPath(data: "M12 4l2.3 4.8 5.2.7-3.8 3.6.9 5.2L12 15.8l-4.6 2.5.9-5.2-3.8-3.6 5.2-.7z").fill(ThanksColors.ink)
        case .channel?:
            SVGPath(data: "M5 10v4h3l6 4V6l-6 4z M17 9.5c1 1.4 1 3.6 0 5")
                .stroke(ThanksColors.ink, style: StrokeStyle(lineWidth: 2 * glyph / 24, lineCap: .round, lineJoin: .round))
        }
    }
}

/// A person's avatar: the downscaled whole photo aspect-filling a circle (never a cropped file), or initials on the
/// canvas gradient; partners get a rounded square (radius 13 of 48). Optional gold badge at the bottom-right (−3 pt).
struct ThanksAvatar: View {
    let person: ThanksPerson
    var size: CGFloat = 48
    var font: CGFloat = 16
    var badge: CGFloat? = 19
    var badgeGlyph: CGFloat = 13
    var index = 0

    private var isPartner: Bool { person.kind != nil }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: isPartner ? size * 13 / 48 : size / 2, style: .circular)
        ZStack {
            if let name = person.photoSmall ?? person.photo, let image = ThanksStore.image(named: name) {
                image.resizable().scaledToFill().frame(width: size, height: size).clipShape(shape)
            } else {
                let palette = isPartner ? ThanksColors.partnerPalette : ThanksColors.avatarPalette
                shape.fill(avatarGradient(palette[index % palette.count], size: size))
                    .overlay(Text(person.initials).font(Typo.fixed(font, .semibold)).kerning(0.02 * font).foregroundStyle(Theme.textPrimary))
            }
        }
        .frame(width: size, height: size)
        .overlay(shape.strokeBorder(Color.white.opacity(0.16), lineWidth: 1))
        .background(shape.fill(Color.black).shadow(color: .black.opacity(0.35), radius: 8, y: 6).opacity(0.999))
        .overlay(alignment: .bottomTrailing) {
            if let badge {
                ThanksBadge(kind: person.kind, size: badge, glyph: badgeGlyph).offset(x: 3, y: 3)
            }
        }
        .accessibilityHidden(true)
    }
}

// MARK: - The app icon

/// The app icon as drawn on the canvas (About, update screens, share sheet): graphite square, aluminium bezel, dial
/// face with 24 ticks, 22 green segments, the marker and the needle (`viewBox 0 0 100` inside the face).
struct TruverAppIconArt: View {
    var size: CGFloat = 96
    var radius: CGFloat = 21

    var body: some View {
        let ring = size * 71.25 / 96, face = size * 61.275 / 96
        ZStack {
            RoundedRectangle(cornerRadius: radius, style: .circular)
                .fill(RadialGradient(stops: [.init(color: Color(hex: 0x2a2d33), location: 0), .init(color: Color(hex: 0x101114), location: 0.6),
                                             .init(color: Color(hex: 0x070708), location: 1)],
                                     center: UnitPoint(x: 0.5, y: 0.22), startRadius: 0, endRadius: 0.9 * size))
            Circle().fill(Theme.metal)
                .frame(width: ring, height: ring)
                .shadow(color: .black.opacity(0.6), radius: size * 2.8125 / 96, y: size * 2.8125 / 96)
            Circle()
                .fill(RadialGradient(stops: [.init(color: Color(hex: 0x1e2024), location: 0), .init(color: Color(hex: 0x0a0a0b), location: 0.7)],
                                     center: UnitPoint(x: 0.5, y: 0.38), startRadius: 0, endRadius: face * 0.7965))
                .frame(width: face, height: face)
                // inset 0 0.94 2.25 rgba(0,0,0,0.9) (for 96 pt): a dark rim inside the face, heavier at the top.
                .overlay(
                    Canvas { ctx, s in
                        let k = size / 96
                        var ring = Path(CGRect(x: -s.width, y: -s.height, width: 3 * s.width, height: 3 * s.height))
                        ring.addEllipse(in: CGRect(origin: CGPoint(x: 0, y: 0.9375 * k), size: s))
                        ctx.addFilter(.blur(radius: 1.125 * k))
                        ctx.fill(ring, with: .color(.black.opacity(0.9)), style: FillStyle(eoFill: true))
                    }
                    .clipShape(Circle())
                )
            Canvas { ctx, s in
                let k = s.width / 100
                let c = CGPoint(x: 50 * k, y: 50 * k)
                func arc(_ r: Double, _ from: Double, _ to: Double) -> Path {
                    var p = Path()
                    p.addArc(center: c, radius: r * k, startAngle: .degrees(from), endAngle: .degrees(to), clockwise: false)
                    return p
                }
                for i in 0..<24 {
                    let mid = -90.0 + Double(i) * 15
                    ctx.stroke(arc(44, mid - 0.35, mid + 0.35), with: .color(Color(red: 233 / 255, green: 230 / 255, blue: 223 / 255, opacity: 0.6)), lineWidth: 3.2 * k)
                }
                for i in 0..<22 {
                    let start = -72.0 + Double(i) * 15
                    ctx.stroke(arc(32, start, start + 9), with: .color(Theme.inTune), lineWidth: 6.5 * k)
                }
                var marker = Path()
                marker.move(to: CGPoint(x: 50 * k, y: 11.5 * k))
                marker.addLine(to: CGPoint(x: 45.4 * k, y: 3.2 * k))
                marker.addLine(to: CGPoint(x: 54.6 * k, y: 3.2 * k))
                marker.closeSubpath()
                ctx.fill(marker, with: .color(Theme.inTune))
                var glow = ctx
                glow.addFilter(.shadow(color: Theme.inTune, radius: 0.8 * k))
                glow.fill(Path(roundedRect: CGRect(x: 48 * k, y: 12.5 * k, width: 4 * k, height: 15 * k), cornerRadius: 2 * k), with: .color(Theme.inTune))
            }
            .frame(width: face, height: face)
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: radius, style: .circular))
        .accessibilityLabel("Значок Truver")
    }
}

// MARK: - Buttons

/// Ivory capsule action of the canvas (`linear-gradient(180deg, #f6f3ec, #d9d4c8)`, 15 semibold, padding 0 18).
struct IvoryCapsuleButton: View {
    let title: String
    var height: CGFloat = 44
    var fullWidth = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title).font(Typo.inter(15, .semibold)).foregroundStyle(Theme.background)
                .lineLimit(1)
                .padding(.horizontal, 18)
                .frame(maxWidth: fullWidth ? .infinity : nil)
                .frame(height: height)
                .background(Capsule().fill(Theme.primaryFill))
        }
        .buttonStyle(PressableStyle())
    }
}

/// Graphite capsule (`card fill`, 1 pt white 8 % border, 15 medium body).
struct GraphiteCapsuleButton: View {
    let title: String
    var height: CGFloat = 44
    var width: CGFloat?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title).font(Typo.inter(15, .medium)).foregroundStyle(Theme.textBody)
                .lineLimit(1)
                .padding(.horizontal, 18)
                .frame(width: width, height: height)
                .background(Capsule().fill(Theme.cardFill))
                .overlay(Capsule().strokeBorder(Theme.hairline, lineWidth: 1))
        }
        .buttonStyle(PressableStyle())
    }
}
