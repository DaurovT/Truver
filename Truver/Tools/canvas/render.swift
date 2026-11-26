import AppKit
import WebKit

// usage: render <outDir> <file.dc.html>...   (TRUVER_RENDER_SCALE=1.5 by default: on a 2× (Retina) Mac that gives 1170 × 2532 for a 390 × 844 board, like a 3× screenshot)
let renderScale = Double(ProcessInfo.processInfo.environment["TRUVER_RENDER_SCALE"] ?? "1.5") ?? 3
let args = CommandLine.arguments
let outDir = args[1]
let files = Array(args.dropFirst(2))
let fontDir = "/Users/timurdaurov/Desktop/TRUVER/Truver/Resources/Fonts/"
let fontCSS = [("ExtraLight",200),("Light",300),("Regular",400),("Medium",500),("SemiBold",600)].map {
  "@font-face{font-family:Inter;font-weight:\($0.1);src:url('file://\(fontDir)Inter-\($0.0).ttf')}"
}.joined() + "@font-face{font-family:Inter;font-weight:700;src:url('file://\(fontDir)Inter-SemiBold.ttf')}"

@MainActor final class R: NSObject, WKNavigationDelegate {
  var queue: [String]; var web: WKWebView!; var size = CGSize(width: 390, height: 844); var current = ""
  init(_ q: [String]) { queue = q }
  func next() {
    guard let f = queue.first else { exit(0) }
    queue.removeFirst(); current = f
    var html = (try? String(contentsOfFile: f, encoding: .utf8)) ?? ""
    if let r = html.range(of: #""width":(\d+),"height":(\d+)"#, options: .regularExpression) {
      let nums = html[r].split(whereSeparator: { !$0.isNumber }).compactMap { Double($0) }
      if nums.count == 2 { size = CGSize(width: nums[0], height: nums[1]) }
    }
    html = html.replacingOccurrences(of: "<script src=\"./support.js\"></script>", with: "")
    html = html.replacingOccurrences(of: "<link href=\"https://fonts.googleapis.com", with: "<link data-x href=\"https://x.invalid")
    html = html.replacingOccurrences(of: "<head>", with: "<head><style>\(fontCSS) *{animation-play-state:paused!important;animation-delay:-0.05s!important} [style*='sheetin'],[style*='fadein'],[style*='popin'],[style*='toastin']{animation:none!important}</style>")
    let cfg = WKWebViewConfiguration()
    web = WKWebView(frame: CGRect(origin: .zero, size: size), configuration: cfg)
    web.navigationDelegate = self
    let tmp = URL(fileURLWithPath: NSTemporaryDirectory() + "dc_render.html")
    try? html.write(to: tmp, atomically: true, encoding: .utf8)
    web.loadFileURL(tmp, allowingReadAccessTo: URL(fileURLWithPath: "/"))
  }
  nonisolated func webView(_ w: WKWebView, didFinish n: WKNavigation!) {
    Task { @MainActor in
      try? await Task.sleep(for: .milliseconds(500))
      let c = WKSnapshotConfiguration(); c.rect = CGRect(origin: .zero, size: self.size); c.snapshotWidth = NSNumber(value: Double(self.size.width) * renderScale)
      self.web.takeSnapshot(with: c) { img, _ in
        if let img, let tiff = img.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff), let png = rep.representation(using: .png, properties: [:]) {
          let name = URL(fileURLWithPath: self.current).deletingPathExtension().deletingPathExtension().lastPathComponent
          try? png.write(to: URL(fileURLWithPath: outDir + "/" + name + ".png"))
          print("ok", name, Int(self.size.width), Int(self.size.height))
        } else { print("fail", self.current) }
        self.next()
      }
    }
  }
}
let app = NSApplication.shared
MainActor.assumeIsolated {
  let r = R(files)
  objc_setAssociatedObject(app, "r", r, .OBJC_ASSOCIATION_RETAIN)
  DispatchQueue.main.async { r.next() }
}
app.run()
