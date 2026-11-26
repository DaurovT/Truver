import SwiftUI
import ImageIO
import TruverTheory

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(.sRGB, red: Double((hex >> 16) & 0xff) / 255, green: Double((hex >> 8) & 0xff) / 255,
                  blue: Double(hex & 0xff) / 255, opacity: opacity)
    }
}

/// Colours of the design canvas «Truver — дизайн iOS и Mac» (graphite, warm white, signal colours).
enum Theme {
    // Ground and surfaces
    static let background = Color(hex: 0x0a0b0d)
    static let backgroundLift = Color(hex: 0x1b1d21)
    static let panel = Color(hex: 0x141518)
    static let panelHigh = Color(hex: 0x26282c)
    static let faceTop = Color(hex: 0x1c1d20)
    static let faceBottom = Color(hex: 0x050506)

    // Text
    static let textPrimary = Color(hex: 0xf6f3ec)
    static let textBody = Color(hex: 0xe9e6df)
    static let textMuted = Color(hex: 0xd9d6cf)
    static let textSecondary = Color(hex: 0xa29f97)
    static let textTertiary = Color(hex: 0x8a877f)

    // Lines and fills
    static let hairline = Color.white.opacity(0.08)
    static let hairlineStrong = Color.white.opacity(0.1)
    static let fill = Color.white.opacity(0.05)
    static let selectedBorder = Color(red: 243 / 255, green: 239 / 255, blue: 230 / 255, opacity: 0.6)

    // Signals
    static let inTune = Color(hex: 0x46e08f)
    static let flat = Color(hex: 0x6aa8ff)
    static let sharp = Color(hex: 0xff9b52)
    static let neutralMark = Color.white.opacity(0.14)
    /// Warm white of metronome beats and the reference tone (canvas «Warm»).
    static let beat = Color(hex: 0xf3efe6)
    static let danger = Color(hex: 0xff6b5e)
    /// Characteristic degree ring on the neck and the «edited» mark (canvas #c3a6ff).
    static let characteristicNote = Color(hex: 0xc3a6ff)
    static let sheetDim = Color(hex: 0x030304, opacity: 0.62)

    /// Light "ivory" used by primary buttons and the selected segment.
    static let accent = Color(hex: 0xece8df)
    static let accentTop = Color(hex: 0xf6f3ec)
    static let accentBottom = Color(hex: 0xd9d4c8)

    // Fretboard roles (FB-3)
    static let tonic = Color(hex: 0xf6f3ec)
    static let chordTone = flat
    static let characteristic = sharp
    static let otherDegree = Color(hex: 0x8a877f)

    static let wood = Color(hex: 0x141518)
    static let fretWire = Color(hex: 0x8d9399)
    static let stringColor = Color(hex: 0xd9dcdf)

    static func color(for role: DegreeRole) -> Color {
        switch role {
        case .tonic: return tonic
        case .chordTone: return chordTone
        case .characteristic: return characteristic
        case .other: return otherDegree
        }
    }

    /// Deviation colour; always paired with a sign and a word (NFR accessibility).
    static func deviationColor(_ cents: Double, inTune: Bool = false) -> Color {
        inTune || abs(cents) <= 3 ? self.inTune : (cents < 0 ? flat : sharp)
    }

    // Gradients
    static let screenBackground = RadialGradient(colors: [backgroundLift, background], center: UnitPoint(x: 0.5, y: 0.28),
                                                 startRadius: 0, endRadius: 520)
    static let cardFill = LinearGradient(colors: [Color.white.opacity(0.055), Color.white.opacity(0.018)], startPoint: .top, endPoint: .bottom)
    static let keyFill = LinearGradient(colors: [Color.white.opacity(0.05), Color.white.opacity(0.015)], startPoint: .top, endPoint: .bottom)
    static let keyFillSelected = LinearGradient(colors: [Color.white.opacity(0.09), Color.white.opacity(0.015)], startPoint: .top, endPoint: .bottom)
    static let primaryFill = LinearGradient(colors: [accentTop, accentBottom], startPoint: .top, endPoint: .bottom)
    static let knobFill = RadialGradient(colors: [panelHigh, panel], center: UnitPoint(x: 0.5, y: 0.35), startRadius: 0, endRadius: 40)
    /// Brushed metal of the dial ring.
    static let metal = AngularGradient(colors: [0x8d9399, 0xeceef0, 0x9aa0a6, 0xdfe2e5, 0x7c8288, 0xf2f3f4, 0xa3a9ae, 0xd9dcdf, 0x858b91, 0xeceef0, 0x8d9399].map { Color(hex: $0) },
                                       center: .center, angle: .degrees(20 - 90))
}

/// The screen ground of every canvas board: `radial-gradient(90% 55% at 50% 28%, #1b1d21 0%, #0a0b0d 70%)` (an
/// ellipse with radii 90 % × 55 % of the screen, the dark colour reached at 70 % of them) and the paper-like noise
/// overlay (`feTurbulence` fractal noise at 7 %, see `ScreenNoise`).
struct ScreenBackground: View {
    var body: some View {
        ZStack {
            Canvas { ctx, size in
                ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Theme.background))
                let rx = size.width * 0.9, ry = size.height * 0.55
                guard rx > 0, ry > 0 else { return }
                ctx.translateBy(x: size.width * 0.5, y: size.height * 0.28)
                ctx.scaleBy(x: 1, y: ry / rx)
                let r = rx * 0.7
                ctx.fill(Path(ellipseIn: CGRect(x: -r, y: -r, width: 2 * r, height: 2 * r)),
                         with: .radialGradient(Gradient(colors: [Theme.backgroundLift, Theme.background]), center: .zero, startRadius: 0, endRadius: r))
            }
            ScreenNoiseView()
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }
}

/// The noise layer of the canvas boards: `<svg opacity=0.07><filter><feTurbulence type=fractalNoise baseFrequency=0.85
/// numOctaves=2 seed=4/><feColorMatrix type=saturate values=0/></filter><rect filter/></svg>` over the whole screen.
/// Computed with the reference algorithm of the SVG specification at the screen's pixel density (matches the canvas
/// render: residual correlation 0.98, mean error 0.7 / 255), once per screen size, off the main thread; cached on disk.
private struct ScreenNoiseView: View {
    @Environment(\.displayScale) private var scale
    @State private var image: CGImage?

    var body: some View {
        GeometryReader { geo in
            let w = Int((geo.size.width * scale).rounded(.up)), h = Int((geo.size.height * scale).rounded(.up))
            ZStack {
                if let image {
                    Image(decorative: image, scale: scale).resizable(resizingMode: .stretch)
                        .interpolation(.none)
                        .frame(width: CGFloat(image.width) / scale, height: CGFloat(image.height) / scale)
                        .opacity(0.07)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: .topLeading)
            .task(id: w * 100_000 + h) {
                guard w > 0, h > 0 else { return }
                if let cached = ScreenNoise.cached(width: w, height: h, scale: scale) { image = cached; return }
                let s = scale
                image = await Task.detached(priority: .utility) { ScreenNoise.image(width: w, height: h, scale: s) }.value
            }
        }
        .allowsHitTesting(false)
    }
}

enum ScreenNoise {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var memory: [String: CGImage] = [:]

    private static func key(_ w: Int, _ h: Int, _ scale: CGFloat) -> String { "noise-\(w)x\(h)@\(Int(scale * 100))" }

    private static func fileURL(_ key: String) -> URL? {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?.appendingPathComponent(key + ".png")
    }

    static func cached(width: Int, height: Int, scale: CGFloat) -> CGImage? {
        let k = key(width, height, scale)
        lock.lock(); defer { lock.unlock() }
        return memory[k]
    }

    /// Gray + alpha noise (premultiplied RGBA8) of `width × height` device pixels at `scale` pixels per point.
    static func image(width: Int, height: Int, scale: CGFloat) -> CGImage? {
        let k = key(width, height, scale)
        if let hit = cached(width: width, height: height, scale: scale) { return hit }
        if let url = fileURL(k), let src = CGImageSourceCreateWithURL(url as CFURL, nil),
           let img = CGImageSourceCreateImageAtIndex(src, 0, nil), img.width == width, img.height == height {
            lock.lock(); memory[k] = img; lock.unlock()
            return img
        }
        let pixels = render(width: width, height: height, scale: Double(scale))
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        guard let provider = CGDataProvider(data: Data(pixels) as CFData),
              let img = CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4, space: space,
                                bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue), provider: provider,
                                decode: nil, shouldInterpolate: false, intent: .defaultIntent) else { return nil }
        lock.lock(); memory[k] = img; lock.unlock()
        if let url = fileURL(k), let dest = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil) {
            CGImageDestinationAddImage(dest, img, nil)
            CGImageDestinationFinalize(dest)
        }
        return img
    }

    /// feTurbulence (fractalNoise, base frequency 0.85, 2 octaves, seed 4) in linearRGB, desaturated
    /// (0.2126 R + 0.7152 G + 0.0722 B), converted to sRGB; alpha is the noise's own alpha channel. WebKit samples the
    /// filter at device pixel (i, j) → user point ((i + 1) / scale, (j + 1) / scale).
    @_optimize(speed)
    static func render(width: Int, height: Int, scale: Double) -> [UInt8] {
        let t = Turbulence(seed: 4)
        var out = [UInt8](repeating: 0, count: width * height * 4)
        var toSRGB = [UInt8](repeating: 0, count: 4096)
        for i in 0..<4096 {
            let v = Double(i) / 4095
            let s = v <= 0.0031308 ? v * 12.92 : 1.055 * pow(v, 1 / 2.4) - 0.055
            toSRGB[i] = UInt8(max(0, min(255, (s * 255).rounded())))
        }
        let f = 0.85 / scale
        out.withUnsafeMutableBufferPointer { buf in
            for j in 0..<height {
                let y = Double(j + 1) * f
                for i in 0..<width {
                    let x = Double(i + 1) * f
                    let r = t.channel(0, x, y), g = t.channel(1, x, y), b = t.channel(2, x, y), a = t.channel(3, x, y)
                    let gray = min(1, max(0, 0.2126 * r + 0.7152 * g + 0.0722 * b))
                    let g8 = Double(toSRGB[Int((gray * 4095).rounded())])
                    let a8 = (a * 255).rounded()
                    let o = (j * width + i) * 4
                    let c = UInt8((g8 * a8 / 255).rounded())
                    buf[o] = c; buf[o + 1] = c; buf[o + 2] = c; buf[o + 3] = UInt8(a8)
                }
            }
        }
        return out
    }

    /// The SVG 1.1 reference implementation of Perlin turbulence (lattice, gradients, `random` of the spec).
    private struct Turbulence {
        private var lattice = [Int](repeating: 0, count: 514)
        private var gradient = [Double](repeating: 0, count: 4 * 514 * 2)

        init(seed: Int) {
            var s = seed
            if s <= 0 { s = -(s % (2147483647 - 1)) + 1 }
            if s > 2147483647 - 1 { s = 2147483647 - 1 }
            func random() -> Int {
                var r = 16807 * (s % 127773) - 2836 * (s / 127773)
                if r <= 0 { r += 2147483647 }
                s = r
                return r
            }
            for k in 0..<4 {
                for i in 0..<256 {
                    lattice[i] = i
                    let a = Double((random() % 512) - 256) / 256, b = Double((random() % 512) - 256) / 256
                    let n = (a * a + b * b).squareRoot()
                    gradient[(k * 514 + i) * 2] = a / n
                    gradient[(k * 514 + i) * 2 + 1] = b / n
                }
            }
            var i = 255
            while i > 0 {
                let k = lattice[i], j = random() % 256
                lattice[i] = lattice[j]; lattice[j] = k
                i -= 1
            }
            for i in 0..<258 {
                lattice[256 + i] = lattice[i]
                for k in 0..<4 {
                    gradient[(k * 514 + 256 + i) * 2] = gradient[(k * 514 + i) * 2]
                    gradient[(k * 514 + 256 + i) * 2 + 1] = gradient[(k * 514 + i) * 2 + 1]
                }
            }
        }

        /// Fractal sum of 2 octaves mapped to 0…1 (`(sum · 255 + 255) / 2`).
        @inline(__always) func channel(_ c: Int, _ x: Double, _ y: Double) -> Double {
            let v = noise(c, x, y) + noise(c, x * 2, y * 2) / 2
            return min(1, max(0, (v + 1) / 2))
        }

        @inline(__always) private func noise(_ c: Int, _ x: Double, _ y: Double) -> Double {
            var t = x + 4096
            let bx0 = Int(t) & 255, bx1 = (bx0 + 1) & 255
            let rx0 = t - Double(Int(t)), rx1 = rx0 - 1
            t = y + 4096
            let by0 = Int(t) & 255, by1 = (by0 + 1) & 255
            let ry0 = t - Double(Int(t)), ry1 = ry0 - 1
            let i = lattice[bx0], j = lattice[bx1]
            let base = c * 514
            let b00 = (base + lattice[i + by0]) * 2, b10 = (base + lattice[j + by0]) * 2
            let b01 = (base + lattice[i + by1]) * 2, b11 = (base + lattice[j + by1]) * 2
            let sx = rx0 * rx0 * (3 - 2 * rx0), sy = ry0 * ry0 * (3 - 2 * ry0)
            var u = rx0 * gradient[b00] + ry0 * gradient[b00 + 1]
            var v = rx1 * gradient[b10] + ry0 * gradient[b10 + 1]
            let a = u + sx * (v - u)
            u = rx0 * gradient[b01] + ry1 * gradient[b01 + 1]
            v = rx1 * gradient[b11] + ry1 * gradient[b11 + 1]
            let b = u + sx * (v - u)
            return a + sy * (b - a)
        }
    }
}
