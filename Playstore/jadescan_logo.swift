import AppKit
import CoreText

// JadeScan "Focus book" logo set: open book between two scanner brackets.
// usage: swiftc -O jadescan_logo.swift -o /tmp/jl && /tmp/jl <fontsDir> <screenshotsDir> <outDir>
let args = CommandLine.arguments
let fontsDir = args[1], shotsDir = args[2], outDir = args[3]
for f in ["ChakraPetch-Medium"] {
  CTFontManagerRegisterFontsForURL(URL(fileURLWithPath: "\(fontsDir)/\(f).ttf") as CFURL, .process, nil)
}

func c(_ hex: UInt32, _ a: CGFloat = 1) -> CGColor {
  CGColor(srgbRed: CGFloat((hex >> 16) & 0xff) / 255, green: CGFloat((hex >> 8) & 0xff) / 255,
          blue: CGFloat(hex & 0xff) / 255, alpha: a)
}
let sRGB = CGColorSpace(name: CGColorSpace.sRGB)!

// Palette, sampled from the chosen mockup.
let bgLight: UInt32 = 0x2C6142, bgDark: UInt32 = 0x133522
let bracket: UInt32 = 0x5FE3AE
let ink: UInt32 = 0x1D3A2C // wordmark on light backgrounds

func canvas(_ w: Int, _ h: Int, opaque: Bool, _ draw: (CGContext) -> Void) -> CGImage {
  let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: sRGB,
                      bitmapInfo: (opaque ? CGImageAlphaInfo.noneSkipLast : CGImageAlphaInfo.premultipliedLast).rawValue)!
  ctx.translateBy(x: 0, y: CGFloat(h)); ctx.scaleBy(x: 1, y: -1)
  NSGraphicsContext.saveGraphicsState()
  NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: true)
  draw(ctx)
  NSGraphicsContext.restoreGraphicsState()
  return ctx.makeImage()!
}
func save(_ img: CGImage, _ name: String) {
  try! NSBitmapImageRep(cgImage: img).representation(using: .png, properties: [:])!
    .write(to: URL(fileURLWithPath: "\(outDir)/\(name)"))
}
func drawImage(_ ctx: CGContext, _ img: CGImage, _ r: CGRect) {
  ctx.saveGState(); ctx.translateBy(x: r.minX, y: r.maxY); ctx.scaleBy(x: 1, y: -1)
  ctx.draw(img, in: CGRect(origin: .zero, size: r.size)); ctx.restoreGState()
}
func linear(_ ctx: CGContext, _ colors: [CGColor], _ a: CGPoint, _ b: CGPoint) {
  let g = CGGradient(colorsSpace: sRGB, colors: colors as CFArray, locations: nil)!
  ctx.drawLinearGradient(g, start: a, end: b, options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
}
func glow(_ ctx: CGContext, _ p: CGPoint, _ r: CGFloat, _ col: CGColor) {
  let g = CGGradient(colorsSpace: sRGB, colors: [col, col.copy(alpha: 0)!] as CFArray, locations: nil)!
  ctx.drawRadialGradient(g, startCenter: p, startRadius: 0, endCenter: p, endRadius: r, options: [])
}

/// Icon background in a 512 x 512 design space, sampled from the mockup:
/// a soft light at the top centre fading to deep, muted green at the bottom,
/// a touch darker on the left.
func background(_ ctx: CGContext) {
  linear(ctx, [c(0x24563A), c(0x173A25), c(0x11301E)], CGPoint(x: 256, y: 0), CGPoint(x: 256, y: 512))
  glow(ctx, CGPoint(x: 300, y: -30), 270, c(0x3B7550, 0.55))
  linear(ctx, [c(0x000000, 0.18), c(0x000000, 0)], CGPoint(x: 0, y: 256), CGPoint(x: 256, y: 256))
}

// Book geometry measured from the mockup, in 512 units; x is the distance
// from the spine. Per side: front page, a band of background green, then
// the back leaf wrapping the outer edge and the bottom.
let seam: CGFloat = 3.3

/// Front page, mirrored by `side` (-1 left, +1 right).
func page(_ side: CGFloat) -> CGPath {
  func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: 256 + side * x, y: y) }
  let path = CGMutablePath()
  path.move(to: p(seam, 205))
  path.addCurve(to: p(112, 153), control1: p(38, 176), control2: p(76, 158))
  path.addLine(to: p(112, 299))
  path.addCurve(to: p(seam, 367), control1: p(68, 303), control2: p(26, 333))
  path.closeSubpath()
  return path
}

/// Back leaf: a light L-shaped band outside and below the front page.
func stack(_ side: CGFloat) -> CGPath {
  func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: 256 + side * x, y: y) }
  let path = CGMutablePath()
  path.move(to: p(148, 193))
  path.addLine(to: p(129, 189.5))
  path.addLine(to: p(129, 317))
  path.addCurve(to: p(seam, 377), control1: p(82, 321), control2: p(30, 348))
  path.addLine(to: p(seam, 384))
  path.addCurve(to: p(148, 345), control1: p(38, 366), control2: p(92, 347))
  path.closeSubpath()
  return path
}

/// The mark in 512 design units. `mono` draws it in one colour (themed icons).
func mark(_ ctx: CGContext, mono: CGColor? = nil, brackets: Bool = true) {
  for side: CGFloat in [-1, 1] {
    for shape in [stack(side), page(side)] {
      if let mono { ctx.addPath(shape); ctx.setFillColor(mono); ctx.fillPath() }
      else { fillGradient(ctx, shape, (0xF4FBF7, 0xBDEAD2), top: 150, bottom: 385) }
    }
  }
  guard brackets else { return }
  ctx.setStrokeColor(mono ?? c(bracket)); ctx.setLineWidth(26); ctx.setLineCap(.round); ctx.setLineJoin(.round)
  ctx.move(to: CGPoint(x: 80, y: 152)); ctx.addLine(to: CGPoint(x: 80, y: 106)); ctx.addLine(to: CGPoint(x: 172, y: 106)); ctx.strokePath()
  ctx.move(to: CGPoint(x: 432, y: 356)); ctx.addLine(to: CGPoint(x: 432, y: 414)); ctx.addLine(to: CGPoint(x: 358, y: 414)); ctx.strokePath()
}

/// Vertical gradient over a fixed band, so every layer shares one light ramp.
func fillGradient(_ ctx: CGContext, _ p: CGPath, _ cols: (UInt32, UInt32), top: CGFloat, bottom: CGFloat) {
  ctx.saveGState(); ctx.addPath(p); ctx.clip()
  linear(ctx, [c(cols.0), c(cols.1)], CGPoint(x: 256, y: top), CGPoint(x: 256, y: bottom))
  ctx.restoreGState()
}

/// Full-bleed square icon (Play Store / iOS: the store applies the corner mask).
func icon(_ size: Int) -> CGImage {
  canvas(size, size, opaque: true) { ctx in
    let k = CGFloat(size) / 512; ctx.scaleBy(x: k, y: k)
    background(ctx); mark(ctx)
  }
}

/// Icon with its own rounded corners and transparent outside (web, docs, slides).
func roundedIcon(_ size: Int) -> CGImage {
  canvas(size, size, opaque: false) { ctx in
    let k = CGFloat(size) / 512; ctx.scaleBy(x: k, y: k)
    ctx.addPath(CGPath(roundedRect: CGRect(x: 0, y: 0, width: 512, height: 512), cornerWidth: 112, cornerHeight: 112, transform: nil))
    ctx.clip(); background(ctx); mark(ctx)
  }
}

/// Android adaptive icon layers, 432 px = 108 dp; the visible 72 dp maps to the 512 design.
func adaptive(_ draw: @escaping (CGContext) -> Void, opaque: Bool, px: Int = 432) -> CGImage {
  canvas(px, px, opaque: opaque) { ctx in
    let k = CGFloat(px) / 432; ctx.scaleBy(x: k, y: k)
    ctx.translateBy(x: 72, y: 72); ctx.scaleBy(x: 288 / 512, y: 288 / 512); draw(ctx)
  }
}

// MARK: - Wordmark: "Jade" bold + "Scan" medium, same colour.
let boldFont = "HelveticaNeue-Bold", mediumFont = "HelveticaNeue"
func wordmarkString(_ size: CGFloat, _ color: CGColor) -> NSAttributedString {
  let s = NSMutableAttributedString(string: "Jade", attributes: [
    .font: NSFont(name: boldFont, size: size)!, .foregroundColor: NSColor(cgColor: color)!, .kern: -size * 0.01])
  s.append(NSAttributedString(string: "Scan", attributes: [
    .font: NSFont(name: mediumFont, size: size)!, .foregroundColor: NSColor(cgColor: color)!, .kern: -size * 0.01]))
  return s
}
func wordmarkWidth(_ size: CGFloat) -> CGFloat { wordmarkString(size, c(ink)).size().width }
func wordmark(_ at: CGPoint, size: CGFloat, color: CGColor) { wordmarkString(size, color).draw(at: at) }

/// Stacked logo as in the mockup: icon above the wordmark, transparent background.
func stacked(onDark: Bool) -> CGImage {
  let w = 1000, h = 1180, iconSize: CGFloat = 760, fontSize: CGFloat = 190
  return canvas(w, h, opaque: false) { ctx in
    ctx.saveGState(); ctx.setShadow(offset: CGSize(width: 0, height: 14), blur: 30, color: c(0x0A2E1D, 0.25))
    drawImage(ctx, roundedIcon(1520), CGRect(x: (CGFloat(w) - iconSize) / 2, y: 50, width: iconSize, height: iconSize))
    ctx.restoreGState()
    let ww = wordmarkWidth(fontSize)
    wordmark(CGPoint(x: (CGFloat(w) - ww) / 2, y: 870), size: fontSize, color: onDark ? c(0xF4FFF8) : c(ink))
  }
}

/// Horizontal lockup: icon + wordmark, transparent background.
func lockup(onDark: Bool) -> CGImage {
  let h = 400, iconSize: CGFloat = 280, gap: CGFloat = 56, fontSize: CGFloat = 168
  let w = Int(60 + iconSize + gap + wordmarkWidth(fontSize) + 60)
  return canvas(w, h, opaque: false) { ctx in
    drawImage(ctx, roundedIcon(560), CGRect(x: 60, y: 60, width: iconSize, height: iconSize))
    let font = NSFont(name: boldFont, size: fontSize)!
    // Centre the capitals on the icon: baseline = middle + capHeight / 2.
    wordmark(CGPoint(x: 60 + iconSize + gap, y: 200 + font.capHeight / 2 - font.ascender),
             size: fontSize, color: onDark ? c(0xF4FFF8) : c(ink))
  }
}

// MARK: - Play feature graphic 1024 x 500
func phone(_ ctx: CGContext, _ shot: CGImage, _ r: CGRect) {
  let body = CGPath(roundedRect: r, cornerWidth: 30, cornerHeight: 30, transform: nil)
  ctx.saveGState(); ctx.setShadow(offset: CGSize(width: 0, height: 18), blur: 40, color: c(0x000000, 0.6))
  ctx.addPath(body); ctx.setFillColor(c(0x0B0F0D)); ctx.fillPath(); ctx.restoreGState()
  let screen = r.insetBy(dx: 8, dy: 8)
  ctx.saveGState()
  ctx.addPath(CGPath(roundedRect: screen, cornerWidth: 23, cornerHeight: 23, transform: nil)); ctx.clip()
  drawImage(ctx, shot, CGRect(x: screen.minX, y: screen.minY, width: screen.width,
                              height: screen.width * CGFloat(shot.height) / CGFloat(shot.width)))
  ctx.restoreGState()
  ctx.addPath(body); ctx.setStrokeColor(c(bracket, 0.35)); ctx.setLineWidth(1.5); ctx.strokePath()
}

func featureGraphic(_ shots: [CGImage]) -> CGImage {
  canvas(1024, 500, opaque: true) { ctx in
    // Same backdrop as the BookToBytes banner (app theme): near-black to
    // emerald, a green glow top right, and the glowing swoosh line.
    linear(ctx, [c(0x0E281C), c(0x0A1F16), c(0x050D0A)], CGPoint(x: 1024, y: 0), CGPoint(x: 0, y: 500))
    glow(ctx, CGPoint(x: 870, y: 25), 768, c(0x1DBF5A, 0.38))
    glow(ctx, CGPoint(x: 102, y: 475), 512, c(0x1DBF5A, 0.10))
    let swoosh = CGMutablePath()
    swoosh.move(to: CGPoint(x: 380, y: -10))
    swoosh.addCurve(to: CGPoint(x: 1040, y: 150), control1: CGPoint(x: 600, y: 120), control2: CGPoint(x: 820, y: 20))
    ctx.saveGState(); ctx.setShadow(offset: .zero, blur: 18, color: c(0x3DFF8A, 0.8))
    ctx.addPath(swoosh); ctx.setStrokeColor(c(0x3DFF8A, 0.55)); ctx.setLineWidth(2.5); ctx.strokePath(); ctx.restoreGState()
    phone(ctx, shots[1], CGRect(x: 830, y: 120, width: 190, height: 420))
    phone(ctx, shots[0], CGRect(x: 650, y: 70, width: 210, height: 460))

    let iconRect = CGRect(x: 64, y: 84, width: 120, height: 120)
    ctx.saveGState(); ctx.setShadow(offset: CGSize(width: 0, height: 12), blur: 26, color: c(0x000000, 0.5))
    drawImage(ctx, roundedIcon(240), iconRect); ctx.restoreGState()
    wordmark(CGPoint(x: 60, y: 222), size: 76, color: c(0xF4FFF8))
    let para = NSMutableParagraphStyle(); para.lineSpacing = 4
    NSAttributedString(string: "Scan books & documents. Export searchable PDF, Word, EPUB and Markdown.",
                       attributes: [.font: NSFont(name: "HelveticaNeue-Medium", size: 24)!,
                                    .foregroundColor: NSColor(cgColor: c(0xC9E8D6))!, .paragraphStyle: para])
      .draw(in: CGRect(x: 64, y: 334, width: 540, height: 120))
  }
}

// MARK: - Render
try! FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)
save(icon(512), "icon_512.png")
save(icon(1024), "icon_1024.png")
save(roundedIcon(1024), "logo_rounded_1024.png")
save(adaptive({ safeMark($0) }, opaque: false), "android_adaptive_foreground_432.png")
save(adaptive({ ctx in ctx.translateBy(x: -128, y: -128); ctx.scaleBy(x: 1.5, y: 1.5); background(ctx) }, opaque: true),
     "android_adaptive_background_432.png")
save(adaptive({ safeMark($0, mono: c(0xFFFFFF)) }, opaque: false), "android_monochrome_432.png")
save(lockup(onDark: false), "lockup_on_light.png")
save(lockup(onDark: true), "lockup_on_dark.png")
save(stacked(onDark: false), "logo_stacked_on_light.png")
save(stacked(onDark: true), "logo_stacked_on_dark.png")
let shots = ["01_home", "06_export_sheet"].map { name -> CGImage in
  let src = CGImageSourceCreateWithURL(URL(fileURLWithPath: "\(shotsDir)/\(name).png") as CFURL, nil)!
  return CGImageSourceCreateImageAtIndex(src, 0, nil)!
}
save(featureGraphic(shots), "feature_graphic_1024x500.png")

// MARK: - App icon sets (app_icons/), ready to copy into the Flutter project.
func saveTo(_ img: CGImage, _ rel: String) {
  let url = URL(fileURLWithPath: "\(outDir)/app_icons/\(rel)")
  try! FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
  try! NSBitmapImageRep(cgImage: img).representation(using: .png, properties: [:])!.write(to: url)
}
func circleIcon(_ size: Int) -> CGImage {
  canvas(size, size, opaque: false) { ctx in
    let k = CGFloat(size) / 512; ctx.scaleBy(x: k, y: k)
    ctx.addEllipse(in: CGRect(x: 0, y: 0, width: 512, height: 512)); ctx.clip(); background(ctx); mark(ctx)
  }
}
/// Web "maskable" icon: full-bleed background, mark inside the 80% safe circle.
func maskable(_ size: Int) -> CGImage {
  canvas(size, size, opaque: true) { ctx in
    let k = CGFloat(size) / 512; ctx.scaleBy(x: k, y: k)
    background(ctx)
    ctx.translateBy(x: 256, y: 256); ctx.scaleBy(x: 0.8, y: 0.8); ctx.translateBy(x: -256, y: -256); mark(ctx)
  }
}
/// Adaptive foreground: the mark at 86% so the corner brackets stay inside
/// Android's 66 dp safe circle on round-mask launchers.
func safeMark(_ ctx: CGContext, mono: CGColor? = nil) {
  ctx.translateBy(x: 256, y: 256); ctx.scaleBy(x: 0.86, y: 0.86); ctx.translateBy(x: -256, y: -256)
  mark(ctx, mono: mono)
}
let adaptiveBackground: (CGContext) -> Void = { ctx in ctx.translateBy(x: -128, y: -128); ctx.scaleBy(x: 1.5, y: 1.5); background(ctx) }
// Android: legacy icons (48 dp) for API < 26, adaptive layers (108 dp) for API 26+.
for (dir, d) in [("mdpi", 1.0), ("hdpi", 1.5), ("xhdpi", 2.0), ("xxhdpi", 3.0), ("xxxhdpi", 4.0)] {
  let legacy = Int(48 * d), layer = Int(108 * d)
  saveTo(roundedIcon(legacy), "android/mipmap-\(dir)/ic_launcher.png")
  saveTo(circleIcon(legacy), "android/mipmap-\(dir)/ic_launcher_round.png")
  saveTo(adaptive({ safeMark($0) }, opaque: false, px: layer), "android/mipmap-\(dir)/ic_launcher_foreground.png")
  saveTo(adaptive(adaptiveBackground, opaque: true, px: layer), "android/mipmap-\(dir)/ic_launcher_background.png")
  saveTo(adaptive({ safeMark($0, mono: c(0xFFFFFF)) }, opaque: false, px: layer), "android/mipmap-\(dir)/ic_launcher_monochrome.png")
}
saveTo(icon(512), "android/playstore_icon_512.png")
// iOS: opaque, square (iOS applies the corner mask). Names match Runner's AppIcon set.
for (name, px) in [("20x20@1x", 20), ("20x20@2x", 40), ("20x20@3x", 60), ("29x29@1x", 29), ("29x29@2x", 58),
                   ("29x29@3x", 87), ("40x40@1x", 40), ("40x40@2x", 80), ("40x40@3x", 120), ("60x60@2x", 120),
                   ("60x60@3x", 180), ("76x76@1x", 76), ("76x76@2x", 152), ("83.5x83.5@2x", 167), ("1024x1024@1x", 1024)] {
  saveTo(icon(px), "ios/AppIcon.appiconset/Icon-App-\(name).png")
}
// Web / PWA.
saveTo(roundedIcon(16), "web/favicon-16.png")
saveTo(roundedIcon(32), "web/favicon-32.png")
saveTo(icon(180), "web/apple-touch-icon.png")
saveTo(roundedIcon(192), "web/icon-192.png")
saveTo(roundedIcon(512), "web/icon-512.png")
saveTo(maskable(192), "web/icon-maskable-192.png")
saveTo(maskable(512), "web/icon-maskable-512.png")

// Preview sheet: stacked logo on light and dark, launcher sizes.
let sheet = canvas(1600, 1080, opaque: true) { ctx in
  ctx.setFillColor(c(0xEAF8F0)); ctx.fill(CGRect(x: 0, y: 0, width: 800, height: 1080))
  ctx.setFillColor(c(0x0D1512)); ctx.fill(CGRect(x: 800, y: 0, width: 800, height: 1080))
  drawImage(ctx, stacked(onDark: false), CGRect(x: 150, y: 40, width: 500, height: 590))
  drawImage(ctx, stacked(onDark: true), CGRect(x: 950, y: 40, width: 500, height: 590))
  for (i, s) in [96.0, 64.0, 48.0, 32.0].enumerated() {
    let x = 170 + CGFloat(i) * 140
    for base: CGFloat in [0, 800] {
      let rect = CGRect(x: base + x, y: 760 - s / 2, width: s, height: s)
      ctx.saveGState(); ctx.addPath(CGPath(ellipseIn: rect, transform: nil)); ctx.clip()
      drawImage(ctx, icon(256), rect); ctx.restoreGState()
    }
  }
  let l = lockup(onDark: false), d = lockup(onDark: true)
  let lw: CGFloat = 560, lh = lw * CGFloat(l.height) / CGFloat(l.width)
  drawImage(ctx, l, CGRect(x: 120, y: 850, width: lw, height: lh))
  drawImage(ctx, d, CGRect(x: 920, y: 850, width: lw, height: lh))
}
save(sheet, "_preview.png")
print("wrote JadeScan logo set to \(outDir)")
