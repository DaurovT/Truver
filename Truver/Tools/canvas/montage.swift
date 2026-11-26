import AppKit
let args = CommandLine.arguments
let out = args[1]
let files = Array(args.dropFirst(2))
let images = files.compactMap { NSImage(contentsOfFile: $0) }
let h: CGFloat = 900
let widths = images.map { h * $0.size.width / $0.size.height }
let total = widths.reduce(0, +) + CGFloat(images.count - 1) * 10
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(total), pixelsHigh: Int(h), bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
NSColor.white.setFill(); NSRect(x: 0, y: 0, width: total, height: h).fill()
var x: CGFloat = 0
for (img, w) in zip(images, widths) { img.draw(in: NSRect(x: x, y: 0, width: w, height: h)); x += w + 10 }
NSGraphicsContext.restoreGraphicsState()
try! rep.representation(using: .jpeg, properties: [.compressionFactor: 0.8])!.write(to: URL(fileURLWithPath: out))
