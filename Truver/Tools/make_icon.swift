// Renders the Truver app icon from the geometry of the design canvas («Бренд — значок приложения»).
// Usage: swift make_icon.swift <output-dir>
import AppKit
import CoreGraphics
import Foundation

let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "."

func color(_ hex: UInt32, _ a: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xff) / 255, green: CGFloat((hex >> 8) & 0xff) / 255, blue: CGFloat(hex & 0xff) / 255, alpha: a)
}

struct Variant {
    var background: [(UInt32, CGFloat)]        // radial stops
    var backgroundCenterY: CGFloat
    var metal: [UInt32]
    var faceTop: UInt32, faceBottom: UInt32, faceCenterY: CGFloat
    var ticks: CGColor
    var signal: CGColor
}

let dark = Variant(background: [(0x2a2d33, 0), (0x101114, 0.6), (0x070708, 1)], backgroundCenterY: 0.22,
                   metal: [0x8d9399, 0xeceef0, 0x9aa0a6, 0xdfe2e5, 0x7c8288, 0xf2f3f4, 0xa3a9ae, 0xd9dcdf, 0x858b91, 0xeceef0, 0x8d9399],
                   faceTop: 0x1e2024, faceBottom: 0x0a0a0b, faceCenterY: 0.38,
                   ticks: CGColor(srgbRed: 233 / 255, green: 230 / 255, blue: 223 / 255, alpha: 0.6), signal: color(0x46e08f))
var light = dark
light.background = [(0xffffff, 0), (0xe7e4dd, 0.75)]
light.backgroundCenterY = 0.25
light.faceTop = 0x26282c
light.faceBottom = 0x0b0b0c
var tinted = dark
tinted.background = [(0x000000, 0), (0x000000, 1)]
tinted.metal = [0x555555, 0xdddddd, 0x666666, 0xbbbbbb, 0x444444, 0xeeeeee, 0x777777, 0xcccccc, 0x555555]
tinted.faceTop = 0x1a1a1a
tinted.faceBottom = 0x050505
tinted.faceCenterY = 0.40
tinted.ticks = CGColor(gray: 1, alpha: 0.55)
tinted.signal = CGColor(gray: 1, alpha: 1)

/// The 22 green arc segments (radius 32 in the face's 100-unit box), from the design file.
let arcs: [(CGFloat, CGFloat, CGFloat, CGFloat)] = [
    (59.889, 19.566, 64.528, 21.488), (67.428, 23.163, 71.412, 26.219), (73.781, 28.588, 76.837, 32.572),
    (78.512, 35.472, 80.434, 40.111), (81.301, 43.347, 81.956, 48.325), (81.956, 51.675, 81.301, 56.653),
    (80.434, 59.889, 78.512, 64.528), (76.837, 67.428, 73.781, 71.412), (71.412, 73.781, 67.428, 76.837),
    (64.528, 78.512, 59.889, 80.434), (56.653, 81.301, 51.675, 81.956), (48.325, 81.956, 43.347, 81.301),
    (40.111, 80.434, 35.472, 78.512), (32.572, 76.837, 28.588, 73.781), (26.219, 71.412, 23.163, 67.428),
    (21.488, 64.528, 19.566, 59.889), (18.699, 56.653, 18.044, 51.675), (18.044, 48.325, 18.699, 43.347),
    (19.566, 40.111, 21.488, 35.472), (23.163, 32.572, 26.219, 28.588), (28.588, 26.219, 32.572, 23.163),
    (35.472, 21.488, 40.111, 19.566),
]

/// Draws the dial (metal ring + face + marks) with the ring's top-left at (x, y) and diameter d, in a y-down context.
func drawDial(_ ctx: CGContext, x: CGFloat, y: CGFloat, ringDiameter d: CGFloat, faceInset: CGFloat, shadowOffset: CGFloat, shadowBlur: CGFloat, v: Variant) {
    let ring = CGRect(x: x, y: y, width: d, height: d)
    let center = CGPoint(x: ring.midX, y: ring.midY)
    // Ring with its drop shadow.
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: shadowOffset), blur: shadowBlur, color: CGColor(gray: 0, alpha: 0.6))
    ctx.addEllipse(in: ring)
    ctx.setFillColor(color(v.metal[0]))
    ctx.fillPath()
    ctx.restoreGState()
    ctx.saveGState()
    ctx.addEllipse(in: ring)
    ctx.clip()
    // Conic gradient (CSS "from 20deg": clockwise from 20° past 12 o'clock) as 720 thin wedges.
    let steps = 720
    let start = (-90.0 + 20.0) * Double.pi / 180
    func rgb(_ hex: UInt32) -> (Double, Double, Double) { (Double((hex >> 16) & 0xff) / 255, Double((hex >> 8) & 0xff) / 255, Double(hex & 0xff) / 255) }
    let cols = v.metal.map(rgb)
    for i in 0..<steps {
        let t = Double(i) / Double(steps) * Double(cols.count - 1)
        let j = min(cols.count - 2, Int(t)), f = t - Double(j)
        let c = (cols[j].0 + (cols[j + 1].0 - cols[j].0) * f, cols[j].1 + (cols[j + 1].1 - cols[j].1) * f, cols[j].2 + (cols[j + 1].2 - cols[j].2) * f)
        let a0 = start + Double(i) / Double(steps) * 2 * .pi
        let a1 = start + Double(i + 1) / Double(steps) * 2 * .pi + 0.002
        ctx.move(to: center)
        ctx.addArc(center: center, radius: d / 2 + 2, startAngle: a0, endAngle: a1, clockwise: false)
        ctx.closePath()
        ctx.setFillColor(CGColor(srgbRed: c.0, green: c.1, blue: c.2, alpha: 1))
        ctx.fillPath()
    }
    ctx.restoreGState()
    // Thin top highlight of the bezel.
    ctx.saveGState()
    ctx.setStrokeColor(CGColor(gray: 1, alpha: 0.5))
    ctx.setLineWidth(d * 0.004)
    ctx.addArc(center: center, radius: d / 2 - d * 0.003, startAngle: .pi * 1.15, endAngle: .pi * 1.85, clockwise: false)
    ctx.strokePath()
    ctx.restoreGState()

    // Face.
    let face = ring.insetBy(dx: faceInset, dy: faceInset)
    ctx.saveGState()
    ctx.addEllipse(in: face)
    ctx.clip()
    let faceGradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
                                  colors: [color(v.faceTop), color(v.faceBottom)] as CFArray, locations: [0, 0.7])!
    let fc = CGPoint(x: face.midX, y: face.minY + face.height * v.faceCenterY)
    ctx.drawRadialGradient(faceGradient, startCenter: fc, startRadius: 0, endCenter: fc, endRadius: face.width * 0.78, options: [.drawsAfterEndLocation])
    // Inset shadow from the top edge.
    ctx.setShadow(offset: CGSize(width: 0, height: face.width * 0.015), blur: face.width * 0.04, color: CGColor(gray: 0, alpha: 0.9))
    ctx.setStrokeColor(CGColor(gray: 0, alpha: 1))
    ctx.setLineWidth(face.width * 0.06)
    ctx.addEllipse(in: face.insetBy(dx: -face.width * 0.03, dy: -face.width * 0.03))
    ctx.strokePath()
    ctx.restoreGState()

    // Marks in the face's 100-unit box (y down).
    let k = face.width / 100
    func p(_ px: CGFloat, _ py: CGFloat) -> CGPoint { CGPoint(x: face.minX + px * k, y: face.minY + py * k) }
    // 24 ticks on r = 44, every 15°, 0.7° long, width 3.2.
    ctx.setStrokeColor(v.ticks)
    ctx.setLineWidth(3.2 * k)
    for i in 0..<24 {
        let mid = (-90 + Double(i) * 15) * .pi / 180
        let half = 0.35 * .pi / 180
        ctx.addArc(center: p(50, 50), radius: 44 * k, startAngle: mid - half, endAngle: mid + half, clockwise: false)
        ctx.strokePath()
    }
    // Green arc: 22 segments on r = 32, width 6.5 (sweep clockwise on screen = increasing angle in y-down).
    ctx.setStrokeColor(v.signal)
    ctx.setLineWidth(6.5 * k)
    ctx.setLineCap(.butt)
    for (x1, y1, x2, y2) in arcs {
        let a1 = atan2(y1 - 50, x1 - 50), a2raw = atan2(y2 - 50, x2 - 50)
        let a2 = a2raw < a1 ? a2raw + 2 * .pi : a2raw
        ctx.addArc(center: p(50, 50), radius: 32 * k, startAngle: a1, endAngle: a2, clockwise: false)
        ctx.strokePath()
    }
    // Needle with its mark: a triangle on the rim and a short glowing bar.
    ctx.setFillColor(v.signal)
    ctx.move(to: p(50, 11.5)); ctx.addLine(to: p(45.4, 3.2)); ctx.addLine(to: p(54.6, 3.2)); ctx.closePath()
    ctx.fillPath()
    ctx.saveGState()
    ctx.setShadow(offset: .zero, blur: 1.6 * k * 2, color: v.signal)
    ctx.addPath(CGPath(roundedRect: CGRect(x: face.minX + 48 * k, y: face.minY + 12.5 * k, width: 4 * k, height: 15 * k),
                       cornerWidth: 2 * k, cornerHeight: 2 * k, transform: nil))
    ctx.fillPath()
    ctx.restoreGState()
}

func makeContext(_ size: Int) -> CGContext {
    let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.translateBy(x: 0, y: CGFloat(size))
    ctx.scaleBy(x: 1, y: -1)   // y down, like the design
    ctx.interpolationQuality = .high
    return ctx
}

func fillBackground(_ ctx: CGContext, rect: CGRect, v: Variant) {
    let g = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: v.background.map { color($0.0) } as CFArray,
                       locations: v.background.map(\.1))!
    let c = CGPoint(x: rect.midX, y: rect.minY + rect.height * v.backgroundCenterY)
    ctx.saveGState()
    ctx.clip(to: rect)
    ctx.drawRadialGradient(g, startCenter: c, startRadius: 0, endCenter: c, endRadius: rect.width * 0.9, options: [.drawsAfterEndLocation])
    ctx.restoreGState()
}

func save(_ ctx: CGContext, _ name: String, opaque: Bool) {
    var image = ctx.makeImage()!
    if opaque {
        // App Store icons must not have an alpha channel.
        let flat = CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: 0,
                             space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
        flat.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        image = flat.makeImage()!
    }
    let rep = NSBitmapImageRep(cgImage: image)
    try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out).appendingPathComponent(name))
    print("wrote", name)
}

// iOS: full-bleed 1024 square; the system draws the corner mask. Ring 74.2 % of the side, face inset 5.2 %.
for (name, v) in [("icon-ios-dark.png", dark), ("icon-ios-light.png", light), ("icon-ios-tinted.png", tinted)] {
    let s: CGFloat = 1024
    let ctx = makeContext(1024)
    fillBackground(ctx, rect: CGRect(x: 0, y: 0, width: s, height: s), v: v)
    let ring = s * 326.5625 / 440
    drawDial(ctx, x: (s - ring) / 2, y: (s - ring) / 2, ringDiameter: ring, faceInset: s * 22.859375 / 440,
             shadowOffset: s * 12.890625 / 440, shadowBlur: s * 25.78125 / 440, v: v)
    save(ctx, name, opaque: true)
}

// macOS: 1024 canvas, 824 body with a drop shadow, corner radius ≈ 22.3 % (design: 79 / 354).
do {
    let s: CGFloat = 1024, body: CGFloat = 824
    let ctx = makeContext(1024)
    let rect = CGRect(x: (s - body) / 2, y: s * 40.390625 / 440, width: body, height: body)
    let radius = body * 79 / 354
    let shape = CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: s * 6.015625 / 440), blur: s * 7.734375 / 440 * 2, color: CGColor(gray: 0, alpha: 0.45))
    ctx.addPath(shape)
    ctx.setFillColor(color(0x101114))
    ctx.fillPath()
    ctx.restoreGState()
    ctx.saveGState()
    ctx.addPath(shape)
    ctx.clip()
    fillBackground(ctx, rect: rect, v: dark)
    let ring = body * 262.734375 / 354
    drawDial(ctx, x: rect.midX - ring / 2, y: rect.midY - ring / 2, ringDiameter: ring, faceInset: body * 18.391406 / 354,
             shadowOffset: body * 10.371094 / 354, shadowBlur: body * 20.742188 / 354, v: dark)
    ctx.restoreGState()
    save(ctx, "icon-mac-1024.png", opaque: false)
}
