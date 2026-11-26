// Side-by-side check of a Flutter screen against the iOS app: «iOS | Flutter | difference».
//   swift tool/compare.swift <ios.png> <flutter.png> <out.jpg> [--top 141] [--rows 141-330,2100-2532]
// Both images are 1170 × 2532 (iPhone 17e, 390 × 844 pt at 3×). The difference panel is |a − b| × 4 on
// black, so a perfect port is black; `--top N` blanks the top N pixels (the status bar, which Flutter does
// not draw) before comparing. Prints the share of pixels that differ by more than 24/255.
import AppKit

let args = CommandLine.arguments
guard args.count >= 4 else {
    print("usage: compare <ios.png> <flutter.png> <out.jpg> [--top N]")
    exit(1)
}
var top = 141   // 47 pt status bar area at 3×
if let i = args.firstIndex(of: "--top"), i + 1 < args.count, let n = Int(args[i + 1]) { top = n }
// `--rows a-b,c-d`: compare only these pixel rows (e.g. the shell's header and tab bar over a screen that is not
// ported yet); other rows are blanked in the difference panel and not counted.
var rowRanges: [ClosedRange<Int>] = []
if let i = args.firstIndex(of: "--rows"), i + 1 < args.count {
    for part in args[i + 1].split(separator: ",") {
        let ends = part.split(separator: "-").compactMap { Int($0) }
        if ends.count == 2 { rowRanges.append(ends[0]...ends[1]) }
    }
}

func bitmap(_ path: String) -> NSBitmapImageRep {
    guard let image = NSImage(contentsOfFile: path), let tiff = image.tiffRepresentation,
          let rep = NSBitmapImageRep(data: tiff) else {
        print("cannot read \(path)")
        exit(1)
    }
    // Normalise to 8-bit RGBA, 1170 × 2532.
    let out = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 1170, pixelsHigh: 2532, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 1170 * 4, bitsPerPixel: 32)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: out)
    rep.draw(in: NSRect(x: 0, y: 0, width: 1170, height: 2532))
    NSGraphicsContext.restoreGraphicsState()
    return out
}

let a = bitmap(args[1]), b = bitmap(args[2])
let w = 1170, h = 2532
let diff = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: w, pixelsHigh: h, bitsPerSample: 8, samplesPerPixel: 4,
                            hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: w * 4, bitsPerPixel: 32)!
let pa = a.bitmapData!, pb = b.bitmapData!, pd = diff.bitmapData!
var differing = 0, counted = 0
for y in 0..<h {
    for x in 0..<w {
        let i = (y * w + x) * 4
        if y < top || (!rowRanges.isEmpty && !rowRanges.contains { $0.contains(y) }) {
            pd[i] = 0; pd[i + 1] = 0; pd[i + 2] = 0; pd[i + 3] = 255
            continue
        }
        var maxDelta = 0
        for c in 0..<3 {
            let d = abs(Int(pa[i + c]) - Int(pb[i + c]))
            maxDelta = max(maxDelta, d)
            pd[i + c] = UInt8(min(255, d * 4))
        }
        pd[i + 3] = 255
        counted += 1
        if maxDelta > 24 { differing += 1 }
    }
}

let panelH: CGFloat = 1266, panelW: CGFloat = 585, gap: CGFloat = 12
let total = panelW * 3 + gap * 2
let sheet = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(total), pixelsHigh: Int(panelH + 40), bitsPerSample: 8,
                             samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: sheet)
NSColor(white: 0.35, alpha: 1).setFill()
NSRect(x: 0, y: 0, width: total, height: panelH + 40).fill()
for (k, rep) in [a, b, diff].enumerated() {
    rep.draw(in: NSRect(x: CGFloat(k) * (panelW + gap), y: 0, width: panelW, height: panelH))
    let label = ["iOS", "Flutter", "разница ×4"][k] as NSString
    label.draw(at: NSPoint(x: CGFloat(k) * (panelW + gap) + 8, y: panelH + 10),
               withAttributes: [.font: NSFont.systemFont(ofSize: 20, weight: .medium), .foregroundColor: NSColor.white])
}
NSGraphicsContext.restoreGraphicsState()
try! sheet.representation(using: .jpeg, properties: [.compressionFactor: 0.85])!.write(to: URL(fileURLWithPath: args[3]))
let share = Double(differing) / Double(max(1, counted)) * 100
print(String(format: "differing pixels: %.2f%% → %@", share, args[3]))
