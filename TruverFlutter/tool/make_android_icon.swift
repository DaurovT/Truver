// Android launcher icon from the same geometry as the iOS icon (Truver/Tools/make_icon.swift).
// Run via tool/make_android_icon.sh — it prepends make_icon.swift (drawDial, fillBackground, variants).
//
// Adaptive icon (API 26+): 108 dp layers, the launcher shows the inner 72 dp through its mask. The iOS icon's
// ring is 74.2 % of the visible square, so here it is 74.2 % of 72 dp = 53.4 dp — inside the 66 dp safe zone.
// Monochrome layer (Android 13 themed icons): the marks of the dial as a white silhouette.
import AppKit

let res = CommandLine.arguments.count > 2 ? CommandLine.arguments[2] : "res"
let densities: [(String, CGFloat)] = [("mdpi", 1), ("hdpi", 1.5), ("xhdpi", 2), ("xxhdpi", 3), ("xxxhdpi", 4)]

func savePNG(_ ctx: CGContext, _ path: String) {
    let rep = NSBitmapImageRep(cgImage: ctx.makeImage()!)
    try! FileManager.default.createDirectory(atPath: (path as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
    try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: path))
}

for (name, scale) in densities {
    let layer = Int(108 * scale)
    let s = CGFloat(layer)
    let visible = 72 * scale
    let ring = visible * 326.5625 / 440
    let unit = visible / 440   // the iOS design is a 440-unit square

    // Background: the iOS dark radial ground over the whole layer.
    let bg = makeContext(layer)
    fillBackground(bg, rect: CGRect(x: 0, y: 0, width: s, height: s), v: dark)
    savePNG(bg, "\(res)/mipmap-\(name)/ic_launcher_background.png")

    // Foreground: the dial, transparent around it.
    let fg = makeContext(layer)
    drawDial(fg, x: (s - ring) / 2, y: (s - ring) / 2, ringDiameter: ring, faceInset: 22.859375 * unit,
             shadowOffset: 12.890625 * unit, shadowBlur: 25.78125 * unit, v: dark)
    savePNG(fg, "\(res)/mipmap-\(name)/ic_launcher_foreground.png")

    // Monochrome: ring outline, 24 ticks, the arc and the needle in white.
    let mono = makeContext(layer)
    let face = CGRect(x: (s - ring) / 2 + 22.859375 * unit, y: (s - ring) / 2 + 22.859375 * unit,
                      width: ring - 2 * 22.859375 * unit, height: ring - 2 * 22.859375 * unit)
    let k = face.width / 100
    func p(_ px: CGFloat, _ py: CGFloat) -> CGPoint { CGPoint(x: face.minX + px * k, y: face.minY + py * k) }
    mono.setStrokeColor(CGColor(gray: 1, alpha: 1))
    mono.setFillColor(CGColor(gray: 1, alpha: 1))
    mono.setLineWidth(ring * 0.05)
    mono.addEllipse(in: CGRect(x: (s - ring) / 2, y: (s - ring) / 2, width: ring, height: ring).insetBy(dx: ring * 0.025, dy: ring * 0.025))
    mono.strokePath()
    mono.setLineWidth(3.2 * k)
    for i in 0..<24 {
        let mid = (-90 + Double(i) * 15) * .pi / 180, half = 0.35 * .pi / 180
        mono.addArc(center: p(50, 50), radius: 44 * k, startAngle: mid - half, endAngle: mid + half, clockwise: false)
        mono.strokePath()
    }
    mono.setLineWidth(6.5 * k)
    for (x1, y1, x2, y2) in arcs {
        let a1 = atan2(y1 - 50, x1 - 50), a2raw = atan2(y2 - 50, x2 - 50)
        mono.addArc(center: p(50, 50), radius: 32 * k, startAngle: a1, endAngle: a2raw < a1 ? a2raw + 2 * .pi : a2raw, clockwise: false)
        mono.strokePath()
    }
    mono.move(to: p(50, 11.5)); mono.addLine(to: p(45.4, 3.2)); mono.addLine(to: p(54.6, 3.2)); mono.closePath()
    mono.fillPath()
    mono.addPath(CGPath(roundedRect: CGRect(x: face.minX + 48 * k, y: face.minY + 12.5 * k, width: 4 * k, height: 15 * k),
                        cornerWidth: 2 * k, cornerHeight: 2 * k, transform: nil))
    mono.fillPath()
    savePNG(mono, "\(res)/mipmap-\(name)/ic_launcher_monochrome.png")

    // Legacy square icon (pre-adaptive launchers, store listing previews): the iOS dark icon at 48 dp.
    let legacySize = Int(48 * scale)
    let legacy = makeContext(legacySize)
    let ls = CGFloat(legacySize)
    fillBackground(legacy, rect: CGRect(x: 0, y: 0, width: ls, height: ls), v: dark)
    let lr = ls * 326.5625 / 440
    drawDial(legacy, x: (ls - lr) / 2, y: (ls - lr) / 2, ringDiameter: lr, faceInset: ls * 22.859375 / 440,
             shadowOffset: ls * 12.890625 / 440, shadowBlur: ls * 25.78125 / 440, v: dark)
    savePNG(legacy, "\(res)/mipmap-\(name)/ic_launcher.png")
}
print("android icons →", res)
