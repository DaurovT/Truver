import SwiftUI

/// SVG path data (`d="M28 4C40 4 …z"`) as a SwiftUI path — the «Спасибо» page draws the canvas glyphs (the gold
/// plectrum, platform tiles, partner badges) from the same path strings. Supports M L H V C S Q T A Z, relative
/// and absolute; arcs become cubic Béziers.
struct SVGPath: Shape {
    let data: String
    /// The `viewBox` side (all canvas glyphs are square: 24 or 56).
    var viewBox: CGFloat = 24

    func path(in rect: CGRect) -> Path {
        let s = min(rect.width, rect.height) / viewBox
        let path = SVGPath.parse(data)
        return path.applying(CGAffineTransform(translationX: rect.midX - viewBox / 2 * s, y: rect.midY - viewBox / 2 * s).scaledBy(x: s, y: s))
    }

    nonisolated(unsafe) private static var cache: [String: Path] = [:]

    static func parse(_ d: String) -> Path {
        if let cached = cache[d] { return cached }
        var tokens = Tokenizer(Array(d.utf8))
        var path = Path()
        var current = CGPoint.zero, start = CGPoint.zero
        var lastControl: CGPoint?
        var lastQuad: CGPoint?
        var command: UInt8 = 0
        while let next = tokens.command() ?? (command != 0 ? command : nil) {
            command = next
            let relative = next >= 97
            let c = relative ? next - 32 : next
            func pt() -> CGPoint? {
                guard let x = tokens.number(), let y = tokens.number() else { return nil }
                return relative ? CGPoint(x: current.x + x, y: current.y + y) : CGPoint(x: x, y: y)
            }
            var consumed = true
            switch c {
            case UInt8(ascii: "M"):
                guard let p = pt() else { consumed = false; break }
                path.move(to: p); current = p; start = p
                command = relative ? UInt8(ascii: "l") : UInt8(ascii: "L")   // following pairs are line-tos
                lastControl = nil; lastQuad = nil
            case UInt8(ascii: "L"):
                guard let p = pt() else { consumed = false; break }
                path.addLine(to: p); current = p; lastControl = nil; lastQuad = nil
            case UInt8(ascii: "H"):
                guard let x = tokens.number() else { consumed = false; break }
                current = CGPoint(x: relative ? current.x + x : x, y: current.y)
                path.addLine(to: current); lastControl = nil; lastQuad = nil
            case UInt8(ascii: "V"):
                guard let y = tokens.number() else { consumed = false; break }
                current = CGPoint(x: current.x, y: relative ? current.y + y : y)
                path.addLine(to: current); lastControl = nil; lastQuad = nil
            case UInt8(ascii: "C"):
                guard let c1 = pt(), let c2 = pt(), let p = pt() else { consumed = false; break }
                path.addCurve(to: p, control1: c1, control2: c2); current = p; lastControl = c2; lastQuad = nil
            case UInt8(ascii: "S"):
                let c1 = lastControl.map { CGPoint(x: 2 * current.x - $0.x, y: 2 * current.y - $0.y) } ?? current
                guard let c2 = pt(), let p = pt() else { consumed = false; break }
                path.addCurve(to: p, control1: c1, control2: c2); current = p; lastControl = c2; lastQuad = nil
            case UInt8(ascii: "Q"):
                guard let q = pt(), let p = pt() else { consumed = false; break }
                path.addQuadCurve(to: p, control: q); current = p; lastQuad = q; lastControl = nil
            case UInt8(ascii: "T"):
                let q = lastQuad.map { CGPoint(x: 2 * current.x - $0.x, y: 2 * current.y - $0.y) } ?? current
                guard let p = pt() else { consumed = false; break }
                path.addQuadCurve(to: p, control: q); current = p; lastQuad = q; lastControl = nil
            case UInt8(ascii: "A"):
                guard let rx = tokens.number(), let ry = tokens.number(), let rot = tokens.number(),
                      let large = tokens.flag(), let sweep = tokens.flag(), let p = pt() else { consumed = false; break }
                addArc(&path, from: current, to: p, rx: rx, ry: ry, rotation: rot, large: large, sweep: sweep)
                current = p; lastControl = nil; lastQuad = nil
            case UInt8(ascii: "Z"):
                path.closeSubpath(); current = start; lastControl = nil; lastQuad = nil
                command = 0
            default:
                consumed = false
            }
            if !consumed { break }
        }
        cache[d] = path
        return path
    }

    /// SVG elliptical arc (endpoint parametrisation, spec F.6.5) as cubic Béziers of ≤ 90° each.
    private static func addArc(_ path: inout Path, from p0: CGPoint, to p1: CGPoint, rx rx0: CGFloat, ry ry0: CGFloat,
                               rotation: CGFloat, large: Bool, sweep: Bool) {
        var rx = abs(rx0), ry = abs(ry0)
        guard rx > 0, ry > 0, p0 != p1 else { path.addLine(to: p1); return }
        let phi = rotation * .pi / 180, cosP = cos(phi), sinP = sin(phi)
        let dx = (p0.x - p1.x) / 2, dy = (p0.y - p1.y) / 2
        let x1 = cosP * dx + sinP * dy, y1 = -sinP * dx + cosP * dy
        let lambda = x1 * x1 / (rx * rx) + y1 * y1 / (ry * ry)
        if lambda > 1 { rx *= sqrt(lambda); ry *= sqrt(lambda) }
        let num = rx * rx * ry * ry - rx * rx * y1 * y1 - ry * ry * x1 * x1
        let den = rx * rx * y1 * y1 + ry * ry * x1 * x1
        var k = sqrt(max(0, num / den))
        if large == sweep { k = -k }
        let cx1 = k * rx * y1 / ry, cy1 = -k * ry * x1 / rx
        let cx = cosP * cx1 - sinP * cy1 + (p0.x + p1.x) / 2
        let cy = sinP * cx1 + cosP * cy1 + (p0.y + p1.y) / 2
        func angle(_ ux: CGFloat, _ uy: CGFloat, _ vx: CGFloat, _ vy: CGFloat) -> CGFloat {
            let a = atan2(ux * vy - uy * vx, ux * vx + uy * vy)
            return a
        }
        let theta1 = angle(1, 0, (x1 - cx1) / rx, (y1 - cy1) / ry)
        var delta = angle((x1 - cx1) / rx, (y1 - cy1) / ry, (-x1 - cx1) / rx, (-y1 - cy1) / ry)
        if !sweep && delta > 0 { delta -= 2 * .pi }
        if sweep && delta < 0 { delta += 2 * .pi }
        let segments = max(1, Int(ceil(abs(delta) / (.pi / 2))))
        let step = delta / CGFloat(segments)
        let t = 4.0 / 3.0 * tan(step / 4)
        func point(_ a: CGFloat) -> CGPoint {
            let x = rx * cos(a), y = ry * sin(a)
            return CGPoint(x: cx + cosP * x - sinP * y, y: cy + sinP * x + cosP * y)
        }
        func derivative(_ a: CGFloat) -> CGPoint {
            let x = -rx * sin(a), y = ry * cos(a)
            return CGPoint(x: cosP * x - sinP * y, y: sinP * x + cosP * y)
        }
        var a = theta1
        for i in 0..<segments {
            let b = a + step
            let pa = point(a), pb = i == segments - 1 ? p1 : point(b)
            let da = derivative(a), db = derivative(b)
            path.addCurve(to: pb,
                          control1: CGPoint(x: pa.x + t * da.x, y: pa.y + t * da.y),
                          control2: CGPoint(x: pb.x - t * db.x, y: pb.y - t * db.y))
            a = b
        }
    }

    private struct Tokenizer {
        let bytes: [UInt8]
        var i = 0
        init(_ bytes: [UInt8]) { self.bytes = bytes }

        mutating func skip() {
            while i < bytes.count, bytes[i] == 32 || bytes[i] == 44 || bytes[i] == 10 || bytes[i] == 9 || bytes[i] == 13 { i += 1 }
        }

        mutating func command() -> UInt8? {
            skip()
            guard i < bytes.count else { return nil }
            let b = bytes[i]
            if (b >= 65 && b <= 90) || (b >= 97 && b <= 122), b != UInt8(ascii: "e"), b != UInt8(ascii: "E") { i += 1; return b }
            return nil
        }

        mutating func flag() -> Bool? {
            skip()
            guard i < bytes.count else { return nil }
            let b = bytes[i]
            guard b == 48 || b == 49 else { return nil }
            i += 1
            return b == 49
        }

        mutating func number() -> CGFloat? {
            skip()
            let begin = i
            if i < bytes.count, bytes[i] == 45 || bytes[i] == 43 { i += 1 }
            var dot = false, digits = false
            while i < bytes.count {
                let b = bytes[i]
                if b >= 48 && b <= 57 { digits = true; i += 1 }
                else if b == 46 && !dot { dot = true; i += 1 }
                else if (b == 101 || b == 69) && digits {
                    i += 1
                    if i < bytes.count, bytes[i] == 45 || bytes[i] == 43 { i += 1 }
                    while i < bytes.count, bytes[i] >= 48 && bytes[i] <= 57 { i += 1 }
                    break
                } else { break }
            }
            guard digits, let s = String(bytes: bytes[begin..<i], encoding: .ascii), let v = Double(s) else { i = begin; return nil }
            return CGFloat(v)
        }
    }
}
