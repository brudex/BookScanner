import AppKit
import CoreText

// usage: brand <fontsDir> <screenshotsDir> <outRoot>
let args = CommandLine.arguments
let fontsDir = args[1], shotsDir = args[2], outRoot = args[3]
for f in ["ChakraPetch-Bold", "ChakraPetch-SemiBold", "ChakraPetch-Medium"] {
  CTFontManagerRegisterFontsForURL(URL(fileURLWithPath: "\(fontsDir)/\(f).ttf") as CFURL, .process, nil)
}

func c(_ hex: UInt32, _ a: CGFloat = 1) -> CGColor {
  CGColor(srgbRed: CGFloat((hex >> 16) & 0xff) / 255, green: CGFloat((hex >> 8) & 0xff) / 255,
          blue: CGFloat(hex & 0xff) / 255, alpha: a)
}
let accent: UInt32 = 0x3DFF8A, accentDeep: UInt32 = 0x1DBF5A

/// Top-left origin context with AppKit text support.
func canvas(_ w: Int, _ h: Int, opaque: Bool = false, _ draw: (CGContext) -> Void) -> CGImage {
  let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                      space: CGColorSpace(name: CGColorSpace.sRGB)!,
                      bitmapInfo: (opaque ? CGImageAlphaInfo.noneSkipLast : CGImageAlphaInfo.premultipliedLast).rawValue)!
  ctx.translateBy(x: 0, y: CGFloat(h)); ctx.scaleBy(x: 1, y: -1)
  NSGraphicsContext.saveGraphicsState()
  NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: true)
  draw(ctx)
  NSGraphicsContext.restoreGraphicsState()
  return ctx.makeImage()!
}

func save(_ img: CGImage, _ path: String, opaque: Bool = true) {
  var image = img
  if opaque { // Play Store icon/feature graphic: no alpha needed; flatten.
    image = canvas(img.width, img.height, opaque: true) { ctx in
      ctx.setFillColor(c(0x050D0A)); ctx.fill(CGRect(x: 0, y: 0, width: img.width, height: img.height))
      ctx.saveGState(); ctx.translateBy(x: 0, y: CGFloat(img.height)); ctx.scaleBy(x: 1, y: -1)
      ctx.draw(img, in: CGRect(x: 0, y: 0, width: img.width, height: img.height)); ctx.restoreGState()
    }
  }
  let rep = NSBitmapImageRep(cgImage: image)
  try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: path))
}

func drawImage(_ ctx: CGContext, _ img: CGImage, _ r: CGRect) {
  ctx.saveGState(); ctx.translateBy(x: r.minX, y: r.maxY); ctx.scaleBy(x: 1, y: -1)
  ctx.draw(img, in: CGRect(origin: .zero, size: r.size)); ctx.restoreGState()
}

func linear(_ ctx: CGContext, _ colors: [CGColor], _ a: CGPoint, _ b: CGPoint, _ locs: [CGFloat]? = nil) {
  let g = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB)!, colors: colors as CFArray, locations: locs)!
  ctx.drawLinearGradient(g, start: a, end: b, options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
}
func glow(_ ctx: CGContext, _ p: CGPoint, _ r: CGFloat, _ col: CGColor) {
  let g = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
                     colors: [col, col.copy(alpha: 0)!] as CFArray, locations: nil)!
  ctx.drawRadialGradient(g, startCenter: p, startRadius: 0, endCenter: p, endRadius: r, options: [])
}

func background(_ ctx: CGContext, _ w: CGFloat, _ h: CGFloat) {
  linear(ctx, [c(0x0E281C), c(0x0A1F16), c(0x050D0A)], CGPoint(x: w, y: 0), CGPoint(x: 0, y: h))
  glow(ctx, CGPoint(x: w * 0.85, y: h * 0.05), max(w, h) * 0.75, c(accentDeep, 0.38))
  glow(ctx, CGPoint(x: w * 0.1, y: h * 0.95), max(w, h) * 0.5, c(accentDeep, 0.10))
}

// MARK: - JadeScan icon: faceted jade gem inside scanner brackets, with a scan beam.
func jadeIcon(_ s: CGFloat) -> CGImage {
  canvas(Int(s), Int(s)) { ctx in
    background(ctx, s, s)
    let u = s / 512
    ctx.scaleBy(x: u, y: u)
    // Gem silhouette: crown (top) + pavilion (bottom point).
    let tl = CGPoint(x: 196, y: 150), tr = CGPoint(x: 316, y: 150)
    let ml = CGPoint(x: 130, y: 222), mr = CGPoint(x: 382, y: 222)
    let bot = CGPoint(x: 256, y: 384)
    let t1 = CGPoint(x: 226, y: 222), t2 = CGPoint(x: 286, y: 222), tm = CGPoint(x: 256, y: 150)
    func facet(_ pts: [CGPoint], _ top: UInt32, _ bottom: UInt32) {
      let p = CGMutablePath(); p.addLines(between: pts); p.closeSubpath()
      ctx.saveGState(); ctx.addPath(p); ctx.clip()
      let ys = pts.map(\.y)
      linear(ctx, [c(top), c(bottom)], CGPoint(x: 0, y: ys.min()!), CGPoint(x: 0, y: ys.max()!))
      ctx.restoreGState()
      ctx.addPath(p); ctx.setStrokeColor(c(0xCFFFE2, 0.35)); ctx.setLineWidth(2.2); ctx.setLineJoin(.round); ctx.strokePath()
    }
    // Soft glow behind the gem.
    glow(ctx, CGPoint(x: 256, y: 262), 210, c(accent, 0.22))
    // Crown facets.
    facet([tl, ml, t1], 0x5CF2A6, 0x1FB872)
    facet([tl, tm, t1], 0xB9FFD6, 0x4FE39A)
    facet([tm, t1, t2], 0x8CFFC0, 0x35D488)
    facet([tm, tr, t2], 0xD9FFEA, 0x6AF0AC)
    facet([tr, mr, t2], 0x49D995, 0x16995C)
    // Pavilion facets.
    facet([ml, t1, bot], 0x17A866, 0x0B6B40)
    facet([t1, t2, bot], 0x2FD483, 0x0E7F4C)
    facet([t2, mr, bot], 0x0F8A52, 0x075232)
    // Scanner brackets.
    ctx.setStrokeColor(c(accent)); ctx.setLineWidth(24); ctx.setLineCap(.round); ctx.setLineJoin(.round)
    let a: CGFloat = 92, b: CGFloat = 420, L: CGFloat = 70
    for (x, y, dx, dy) in [(a, a, 1.0, 1.0), (b, a, -1.0, 1.0), (a, b, 1.0, -1.0), (b, b, -1.0, -1.0)] {
      ctx.move(to: CGPoint(x: x, y: y + dy * L)); ctx.addLine(to: CGPoint(x: x, y: y))
      ctx.addLine(to: CGPoint(x: x + dx * L, y: y)); ctx.strokePath()
    }
    // Scan beam with glow.
    ctx.saveGState()
    ctx.setShadow(offset: .zero, blur: 26, color: c(accent, 0.95))
    ctx.setStrokeColor(c(0xE9FFF2)); ctx.setLineWidth(7)
    ctx.move(to: CGPoint(x: 118, y: 262)); ctx.addLine(to: CGPoint(x: 394, y: 262)); ctx.strokePath()
    ctx.restoreGState()
  }
}

// MARK: - BookToBytes icon: open book whose right page breaks into pixels.
func bytesIcon(_ s: CGFloat) -> CGImage {
  canvas(Int(s), Int(s)) { ctx in
    background(ctx, s, s)
    let u = s / 512
    ctx.scaleBy(x: u, y: u)
    glow(ctx, CGPoint(x: 256, y: 270), 220, c(accent, 0.18))
    // Left page.
    let left = CGMutablePath()
    left.move(to: CGPoint(x: 250, y: 178))
    left.addCurve(to: CGPoint(x: 92, y: 158), control1: CGPoint(x: 210, y: 150), control2: CGPoint(x: 140, y: 146))
    left.addLine(to: CGPoint(x: 92, y: 362))
    left.addCurve(to: CGPoint(x: 250, y: 384), control1: CGPoint(x: 140, y: 352), control2: CGPoint(x: 210, y: 356))
    left.closeSubpath()
    ctx.saveGState(); ctx.addPath(left); ctx.clip()
    linear(ctx, [c(0xF2FFF7), c(0xBFEFD3)], CGPoint(x: 92, y: 0), CGPoint(x: 250, y: 0))
    ctx.restoreGState()
    // Text lines on the left page.
    ctx.setStrokeColor(c(0x0E5C36, 0.75)); ctx.setLineWidth(9); ctx.setLineCap(.round)
    for i in 0..<6 {
      let y = CGFloat(198 + i * 28), sag = CGFloat(10) - CGFloat(i) * 0.6
      let x2: CGFloat = i == 5 ? 180 : 226
      ctx.move(to: CGPoint(x: 116, y: y)); ctx.addQuadCurve(to: CGPoint(x: x2, y: y + sag * 0.6), control: CGPoint(x: 170, y: y - 4)); ctx.strokePath()
    }
    // Spine.
    ctx.setStrokeColor(c(accent)); ctx.setLineWidth(8)
    ctx.move(to: CGPoint(x: 256, y: 174)); ctx.addLine(to: CGPoint(x: 256, y: 392)); ctx.strokePath()
    // Right page as a pixel grid that dissolves to the upper right.
    var seed: UInt64 = 42
    func rnd() -> CGFloat { seed = seed &* 6364136223846793005 &+ 1442695040888963407; return CGFloat(seed >> 33) / CGFloat(1 << 31) }
    let cell: CGFloat = 22, gap: CGFloat = 4
    for row in 0..<10 {
      for col in 0..<11 {
        let t = CGFloat(col) / 10 // 0 at spine -> 1 far right
        let x0 = 266 + CGFloat(col) * cell
        let arch = 14 * sin(min(1, CGFloat(col) / 7) * .pi) // page curls up like the left one
        var x = x0, y = 172 + CGFloat(row) * cell - arch
        var scale: CGFloat = 1, alpha: CGFloat = 1
        if col >= 4 { // the page breaks into bytes, drifting up and right
          let k = (t - 0.3) / 0.7
          if rnd() < k * 0.95 { continue }
          x += k * 26 * rnd(); y -= k * 46 * rnd() + k * 18
          scale = 1 - k * 0.55; alpha = 1 - k * 0.55
        }
        let size = (cell - gap) * scale
        if x + size > 492 || y < 40 { continue }
        let r = rnd()
        let shade: UInt32 = r < 0.3 ? 0xA8FFCC : r < 0.5 ? accentDeep : accent
        ctx.setFillColor(c(shade, alpha))
        ctx.addPath(CGPath(roundedRect: CGRect(x: x, y: y, width: size, height: size), cornerWidth: 3.5, cornerHeight: 3.5, transform: nil))
        ctx.fillPath()
      }
    }
    // A few loose bytes flying off.
    for (x, y, sz, a) in [(446.0, 118.0, 12.0, 0.6), (472.0, 150.0, 9.0, 0.45), (418.0, 96.0, 9.0, 0.45)] {
      ctx.setFillColor(c(accent, a))
      ctx.addPath(CGPath(roundedRect: CGRect(x: x, y: y, width: sz, height: sz), cornerWidth: 3, cornerHeight: 3, transform: nil)); ctx.fillPath()
    }
  }
}

// MARK: - Feature graphic 1024 x 500.
func text(_ s: String, _ font: String, _ size: CGFloat, _ color: CGColor, _ p: CGPoint, kern: CGFloat = 0, width: CGFloat? = nil) {
  let para = NSMutableParagraphStyle(); para.lineSpacing = 4
  let attrs: [NSAttributedString.Key: Any] = [.font: NSFont(name: font, size: size)!,
                                              .foregroundColor: NSColor(cgColor: color)!, .kern: kern, .paragraphStyle: para]
  let str = NSAttributedString(string: s, attributes: attrs)
  if let width { str.draw(in: CGRect(x: p.x, y: p.y, width: width, height: 400)) } else { str.draw(at: p) }
}

func phone(_ ctx: CGContext, _ shot: CGImage, _ r: CGRect) {
  let body = CGPath(roundedRect: r, cornerWidth: 30, cornerHeight: 30, transform: nil)
  ctx.saveGState(); ctx.setShadow(offset: CGSize(width: 0, height: 18), blur: 40, color: c(0x000000, 0.6))
  ctx.addPath(body); ctx.setFillColor(c(0x0B0F0D)); ctx.fillPath(); ctx.restoreGState()
  let screen = r.insetBy(dx: 8, dy: 8)
  ctx.saveGState()
  ctx.addPath(CGPath(roundedRect: screen, cornerWidth: 23, cornerHeight: 23, transform: nil)); ctx.clip()
  let h = screen.width * CGFloat(shot.height) / CGFloat(shot.width)
  drawImage(ctx, shot, CGRect(x: screen.minX, y: screen.minY, width: screen.width, height: h))
  ctx.restoreGState()
  ctx.addPath(body); ctx.setStrokeColor(c(accent, 0.35)); ctx.setLineWidth(1.5); ctx.strokePath()
}

func banner(name: [(String, UInt32)], tagline: String, icon: CGImage, shots: [CGImage]) -> CGImage {
  canvas(1024, 500) { ctx in
    background(ctx, 1024, 500)
    // Swoosh like the Home screen.
    let edge = CGMutablePath()
    edge.move(to: CGPoint(x: 380, y: -10))
    edge.addCurve(to: CGPoint(x: 1040, y: 150), control1: CGPoint(x: 600, y: 120), control2: CGPoint(x: 820, y: 20))
    ctx.saveGState(); ctx.setShadow(offset: .zero, blur: 18, color: c(accent, 0.8))
    ctx.addPath(edge); ctx.setStrokeColor(c(accent, 0.55)); ctx.setLineWidth(2.5); ctx.strokePath(); ctx.restoreGState()

    // Phones on the right, bleeding off the bottom.
    phone(ctx, shots[1], CGRect(x: 830, y: 120, width: 190, height: 420))
    phone(ctx, shots[0], CGRect(x: 650, y: 70, width: 210, height: 460))

    // Icon + name + tagline.
    let iconRect = CGRect(x: 64, y: 96, width: 112, height: 112)
    ctx.saveGState(); ctx.setShadow(offset: CGSize(width: 0, height: 10), blur: 24, color: c(0x000000, 0.55))
    ctx.addPath(CGPath(roundedRect: iconRect, cornerWidth: 26, cornerHeight: 26, transform: nil)); ctx.setFillColor(c(0x050D0A)); ctx.fillPath()
    ctx.restoreGState()
    ctx.saveGState(); ctx.addPath(CGPath(roundedRect: iconRect, cornerWidth: 26, cornerHeight: 26, transform: nil)); ctx.clip()
    drawImage(ctx, icon, iconRect); ctx.restoreGState()

    var x: CGFloat = 62
    for (part, color) in name {
      let font = NSFont(name: "ChakraPetch-Bold", size: 66)!
      text(part, "ChakraPetch-Bold", 66, c(color), CGPoint(x: x, y: 228), kern: 0.5)
      x += (part as NSString).size(withAttributes: [.font: font, .kern: 0.5]).width
    }
    text(tagline, "ChakraPetch-Medium", 25, c(0xC9E8D6), CGPoint(x: 66, y: 324), width: 540)
  }
}

let shots = ["01_home", "06_export_sheet"].map { name -> CGImage in
  let src = CGImageSourceCreateWithURL(URL(fileURLWithPath: "\(shotsDir)/\(name).png") as CFURL, nil)!
  return CGImageSourceCreateImageAtIndex(src, 0, nil)!
}

let brands: [(dir: String, icon: (CGFloat) -> CGImage, name: [(String, UInt32)], tag: String)] = [
  ("jadescan", jadeIcon, [("Jade", accent), ("Scan", 0xF2FFF7)],
   "Scan books & documents. Export searchable PDF, Word, EPUB and Markdown."),
  ("booktobytes", bytesIcon, [("Book", 0xF2FFF7), ("To", accent), ("Bytes", 0xF2FFF7)],
   "Turn printed pages into searchable PDF, Word, EPUB and Markdown."),
]
for b in brands {
  let dir = "\(outRoot)/\(b.dir)"
  try! FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
  let icon512 = b.icon(512)
  save(icon512, "\(dir)/icon_512.png")
  save(b.icon(1024), "\(dir)/icon_1024.png")
  save(banner(name: b.name, tagline: b.tag, icon: icon512, shots: shots), "\(dir)/feature_graphic_1024x500.png")
  print("wrote \(dir)")
}
