import AppKit
import CoreText

// JadeScan logo variations.
// usage: swiftc -O jadescan_variations.swift -o /tmp/jv && /tmp/jv <fontsDir> <outDir>
let args = CommandLine.arguments
let fontsDir = args[1], outDir = args[2]
for f in ["ChakraPetch-Bold", "ChakraPetch-SemiBold"] {
  CTFontManagerRegisterFontsForURL(URL(fileURLWithPath: "\(fontsDir)/\(f).ttf") as CFURL, .process, nil)
}

func c(_ hex: UInt32, _ a: CGFloat = 1) -> CGColor {
  CGColor(srgbRed: CGFloat((hex >> 16) & 0xff) / 255, green: CGFloat((hex >> 8) & 0xff) / 255,
          blue: CGFloat(hex & 0xff) / 255, alpha: a)
}
let accent: UInt32 = 0x3DFF8A, accentDeep: UInt32 = 0x1DBF5A
let sRGB = CGColorSpace(name: CGColorSpace.sRGB)!

func canvas(_ w: Int, _ h: Int, opaque: Bool = true, _ draw: (CGContext) -> Void) -> CGImage {
  let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: sRGB,
                      bitmapInfo: (opaque ? CGImageAlphaInfo.noneSkipLast : CGImageAlphaInfo.premultipliedLast).rawValue)!
  ctx.translateBy(x: 0, y: CGFloat(h)); ctx.scaleBy(x: 1, y: -1)
  NSGraphicsContext.saveGraphicsState()
  NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: true)
  draw(ctx)
  NSGraphicsContext.restoreGraphicsState()
  return ctx.makeImage()!
}
func save(_ img: CGImage, _ path: String) {
  try! NSBitmapImageRep(cgImage: img).representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: path))
}
func drawImage(_ ctx: CGContext, _ img: CGImage, _ r: CGRect) {
  ctx.saveGState(); ctx.translateBy(x: r.minX, y: r.maxY); ctx.scaleBy(x: 1, y: -1)
  ctx.draw(img, in: CGRect(origin: .zero, size: r.size)); ctx.restoreGState()
}
func linear(_ ctx: CGContext, _ colors: [CGColor], _ a: CGPoint, _ b: CGPoint, _ locs: [CGFloat]? = nil) {
  let g = CGGradient(colorsSpace: sRGB, colors: colors as CFArray, locations: locs)!
  ctx.drawLinearGradient(g, start: a, end: b, options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
}
func radial(_ ctx: CGContext, _ colors: [CGColor], _ p: CGPoint, _ r: CGFloat, _ locs: [CGFloat]? = nil) {
  let g = CGGradient(colorsSpace: sRGB, colors: colors as CFArray, locations: locs)!
  ctx.drawRadialGradient(g, startCenter: p, startRadius: 0, endCenter: p, endRadius: r, options: [.drawsAfterEndLocation])
}
func glow(_ ctx: CGContext, _ p: CGPoint, _ r: CGFloat, _ col: CGColor) {
  let g = CGGradient(colorsSpace: sRGB, colors: [col, col.copy(alpha: 0)!] as CFArray, locations: nil)!
  ctx.drawRadialGradient(g, startCenter: p, startRadius: 0, endCenter: p, endRadius: r, options: [])
}
func darkBackground(_ ctx: CGContext) {
  linear(ctx, [c(0x0E281C), c(0x0A1F16), c(0x050D0A)], CGPoint(x: 512, y: 0), CGPoint(x: 0, y: 512))
  glow(ctx, CGPoint(x: 435, y: 25), 384, c(accentDeep, 0.38))
  glow(ctx, CGPoint(x: 50, y: 486), 256, c(accentDeep, 0.10))
}
func path(_ pts: [CGPoint]) -> CGPath {
  let p = CGMutablePath(); p.addLines(between: pts); p.closeSubpath(); return p
}
func fill(_ ctx: CGContext, _ p: CGPath, _ top: UInt32, _ bottom: UInt32, vertical: Bool = true) {
  ctx.saveGState(); ctx.addPath(p); ctx.clip()
  let b = p.boundingBox
  linear(ctx, [c(top), c(bottom)], CGPoint(x: vertical ? 0 : b.minX, y: vertical ? b.minY : 0),
         CGPoint(x: vertical ? 0 : b.maxX, y: vertical ? b.maxY : 0))
  ctx.restoreGState()
}

/// Scanner corner brackets around a square [a, b].
func brackets(_ ctx: CGContext, _ a: CGFloat, _ b: CGFloat, len: CGFloat, width: CGFloat, color: CGColor) {
  ctx.setStrokeColor(color); ctx.setLineWidth(width); ctx.setLineCap(.round); ctx.setLineJoin(.round)
  for (x, y, dx, dy) in [(a, a, 1.0, 1.0), (b, a, -1.0, 1.0), (a, b, 1.0, -1.0), (b, b, -1.0, -1.0)] {
    ctx.move(to: CGPoint(x: x, y: y + dy * len)); ctx.addLine(to: CGPoint(x: x, y: y))
    ctx.addLine(to: CGPoint(x: x + dx * len, y: y)); ctx.strokePath()
  }
}
func beam(_ ctx: CGContext, y: CGFloat, from x0: CGFloat, to x1: CGFloat, width: CGFloat = 7, color: UInt32 = 0xE9FFF2) {
  ctx.saveGState()
  ctx.setShadow(offset: .zero, blur: 26, color: c(accent, 0.95))
  ctx.setStrokeColor(c(color)); ctx.setLineWidth(width); ctx.setLineCap(.round)
  ctx.move(to: CGPoint(x: x0, y: y)); ctx.addLine(to: CGPoint(x: x1, y: y)); ctx.strokePath()
  ctx.restoreGState()
}

/// The faceted gem from the first logo, centred at `o`, scaled by `k`.
func gem(_ ctx: CGContext, _ o: CGPoint, _ k: CGFloat, outline: UInt32 = 0xCFFFE2, outlineAlpha: CGFloat = 0.35,
         palette: [(UInt32, UInt32)]? = nil, strokeOnly: Bool = false, strokeWidth: CGFloat = 2.2) {
  func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: o.x + (x - 256) * k, y: o.y + (y - 267) * k) }
  let tl = p(196, 150), tr = p(316, 150), ml = p(130, 222), mr = p(382, 222), bot = p(256, 384)
  let t1 = p(226, 222), t2 = p(286, 222), tm = p(256, 150)
  let facets = [[tl, ml, t1], [tl, tm, t1], [tm, t1, t2], [tm, tr, t2], [tr, mr, t2],
                [ml, t1, bot], [t1, t2, bot], [t2, mr, bot]]
  let colors = palette ?? [(0x5CF2A6, 0x1FB872), (0xB9FFD6, 0x4FE39A), (0x8CFFC0, 0x35D488), (0xD9FFEA, 0x6AF0AC),
                           (0x49D995, 0x16995C), (0x17A866, 0x0B6B40), (0x2FD483, 0x0E7F4C), (0x0F8A52, 0x075232)]
  for (i, f) in facets.enumerated() {
    let fp = path(f)
    if !strokeOnly { fill(ctx, fp, colors[i].0, colors[i].1) }
    ctx.addPath(fp); ctx.setStrokeColor(c(outline, outlineAlpha)); ctx.setLineWidth(strokeWidth * k)
    ctx.setLineJoin(.round); ctx.strokePath()
  }
}

func glyphPath(_ s: String, _ font: String, _ size: CGFloat) -> CGPath {
  let f = CTFontCreateWithName(font as CFString, size, nil)
  let out = CGMutablePath()
  var x: CGFloat = 0
  for ch in s.utf16 {
    var u = ch, g: CGGlyph = 0
    CTFontGetGlyphsForCharacters(f, &u, &g, 1)
    var adv = CGSize.zero
    CTFontGetAdvancesForGlyphs(f, .horizontal, &g, &adv, 1)
    if let gp = CTFontCreatePathForGlyph(f, g, nil) {
      var t = CGAffineTransform(translationX: x, y: 0).scaledBy(x: 1, y: -1) // flip to top-left space
      out.addPath(gp, transform: t); _ = t
      t = .identity
    }
    x += adv.width
  }
  return out
}
func centered(_ p: CGPath, at o: CGPoint) -> CGPath {
  let b = p.boundingBox
  var t = CGAffineTransform(translationX: o.x - b.midX, y: o.y - b.midY)
  return p.copy(using: &t)!
}

// MARK: - Variations (512 design units)
var variations: [(String, String, (CGContext) -> Void)] = []

variations.append(("a_original", "Faceted gem + scanner frame (current)", { ctx in
  darkBackground(ctx)
  glow(ctx, CGPoint(x: 256, y: 262), 210, c(accent, 0.22))
  gem(ctx, CGPoint(x: 256, y: 267), 1)
  brackets(ctx, 92, 420, len: 70, width: 24, color: c(accent))
  beam(ctx, y: 262, from: 118, to: 394)
}))

variations.append(("b_cabochon", "Polished jade stone (cabochon) with scan line", { ctx in
  darkBackground(ctx)
  glow(ctx, CGPoint(x: 256, y: 262), 230, c(accent, 0.20))
  let stone = CGPath(ellipseIn: CGRect(x: 120, y: 160, width: 272, height: 210), transform: nil)
  ctx.saveGState()
  ctx.setShadow(offset: CGSize(width: 0, height: 14), blur: 30, color: c(0x000000, 0.55))
  ctx.addPath(stone); ctx.setFillColor(c(0x0B6B40)); ctx.fillPath(); ctx.restoreGState()
  ctx.saveGState(); ctx.addPath(stone); ctx.clip()
  radial(ctx, [c(0xB6FFD6), c(0x3FE095), c(0x169B5E), c(0x07482B)], CGPoint(x: 220, y: 215), 220, [0, 0.3, 0.7, 1])
  // Translucent veins.
  ctx.setStrokeColor(c(0xE6FFF0, 0.16)); ctx.setLineWidth(10); ctx.setLineCap(.round)
  ctx.move(to: CGPoint(x: 140, y: 300)); ctx.addCurve(to: CGPoint(x: 380, y: 250), control1: CGPoint(x: 220, y: 250), control2: CGPoint(x: 300, y: 330)); ctx.strokePath()
  ctx.setLineWidth(5)
  ctx.move(to: CGPoint(x: 180, y: 345)); ctx.addCurve(to: CGPoint(x: 360, y: 320), control1: CGPoint(x: 240, y: 310), control2: CGPoint(x: 300, y: 360)); ctx.strokePath()
  // Specular highlight.
  glow(ctx, CGPoint(x: 205, y: 200), 70, c(0xFFFFFF, 0.55))
  ctx.restoreGState()
  ctx.addPath(stone); ctx.setStrokeColor(c(0xCFFFE2, 0.45)); ctx.setLineWidth(2.5); ctx.strokePath()
  brackets(ctx, 82, 430, len: 70, width: 24, color: c(accent))
  beam(ctx, y: 266, from: 104, to: 408)
}))

variations.append(("c_monogram_j", "Jade “J” monogram inside a scanner frame", { ctx in
  darkBackground(ctx)
  glow(ctx, CGPoint(x: 256, y: 262), 220, c(accent, 0.18))
  let j = centered(glyphPath("J", "ChakraPetch-Bold", 330), at: CGPoint(x: 262, y: 258))
  ctx.saveGState(); ctx.setShadow(offset: CGSize(width: 0, height: 10), blur: 24, color: c(0x000000, 0.5))
  ctx.addPath(j); ctx.setFillColor(c(0x0B6B40)); ctx.fillPath(); ctx.restoreGState()
  ctx.saveGState(); ctx.addPath(j); ctx.clip()
  linear(ctx, [c(0xC9FFE0), c(0x4FE39A), c(0x139A5C)], CGPoint(x: 160, y: 120), CGPoint(x: 360, y: 400), [0, 0.45, 1])
  // Facet split: darker lower-right half.
  ctx.addPath(path([CGPoint(x: 512, y: 120), CGPoint(x: 512, y: 512), CGPoint(x: 120, y: 512)]))
  ctx.setFillColor(c(0x053A22, 0.28)); ctx.fillPath()
  ctx.restoreGState()
  brackets(ctx, 92, 420, len: 70, width: 24, color: c(accent))
  beam(ctx, y: 262, from: 118, to: 394)
}))

variations.append(("d_page_gem", "Document page with a jade gem", { ctx in
  darkBackground(ctx)
  glow(ctx, CGPoint(x: 256, y: 262), 230, c(accent, 0.16))
  // Page with folded corner.
  let x0: CGFloat = 136, y0: CGFloat = 92, w: CGFloat = 240, h: CGFloat = 320, fold: CGFloat = 64
  let page = CGMutablePath()
  page.move(to: CGPoint(x: x0 + 18, y: y0)); page.addLine(to: CGPoint(x: x0 + w - fold, y: y0))
  page.addLine(to: CGPoint(x: x0 + w, y: y0 + fold)); page.addLine(to: CGPoint(x: x0 + w, y: y0 + h - 18))
  page.addQuadCurve(to: CGPoint(x: x0 + w - 18, y: y0 + h), control: CGPoint(x: x0 + w, y: y0 + h))
  page.addLine(to: CGPoint(x: x0 + 18, y: y0 + h))
  page.addQuadCurve(to: CGPoint(x: x0, y: y0 + h - 18), control: CGPoint(x: x0, y: y0 + h))
  page.addLine(to: CGPoint(x: x0, y: y0 + 18))
  page.addQuadCurve(to: CGPoint(x: x0 + 18, y: y0), control: CGPoint(x: x0, y: y0))
  ctx.saveGState(); ctx.setShadow(offset: CGSize(width: 0, height: 16), blur: 30, color: c(0x000000, 0.55))
  ctx.addPath(page); ctx.setFillColor(c(0xF2FFF7)); ctx.fillPath(); ctx.restoreGState()
  fill(ctx, page, 0xF7FFFA, 0xD3F3E0)
  fill(ctx, path([CGPoint(x: x0 + w - fold, y: y0), CGPoint(x: x0 + w - fold, y: y0 + fold), CGPoint(x: x0 + w, y: y0 + fold)]), 0xA8E8C3, 0x6CCB95)
  // Text lines.
  ctx.setStrokeColor(c(0x0E5C36, 0.35)); ctx.setLineWidth(10); ctx.setLineCap(.round)
  for (i, len) in [172.0, 150.0].enumerated() {
    ctx.move(to: CGPoint(x: x0 + 34, y: y0 + 262 + CGFloat(i) * 26)); ctx.addLine(to: CGPoint(x: x0 + 34 + len, y: y0 + 262 + CGFloat(i) * 26)); ctx.strokePath()
  }
  gem(ctx, CGPoint(x: 256, y: 186), 0.55, outline: 0x0E5C36, outlineAlpha: 0.25)
  beam(ctx, y: 236, from: 108, to: 404, width: 8)
}))

variations.append(("e_light", "Light version (mint background)", { ctx in
  linear(ctx, [c(0xF4FFF8), c(0xD6F7E4)], CGPoint(x: 0, y: 0), CGPoint(x: 512, y: 512))
  glow(ctx, CGPoint(x: 256, y: 262), 220, c(accent, 0.25))
  gem(ctx, CGPoint(x: 256, y: 267), 1, outline: 0xFFFFFF, outlineAlpha: 0.55)
  brackets(ctx, 92, 420, len: 70, width: 24, color: c(0x0E7F4C))
  ctx.saveGState(); ctx.setShadow(offset: .zero, blur: 18, color: c(accentDeep, 0.9))
  ctx.setStrokeColor(c(0x12C46A)); ctx.setLineWidth(7); ctx.setLineCap(.round)
  ctx.move(to: CGPoint(x: 118, y: 262)); ctx.addLine(to: CGPoint(x: 394, y: 262)); ctx.strokePath(); ctx.restoreGState()
}))

variations.append(("f_hex_tile", "Hexagonal jade tile with scan line", { ctx in
  darkBackground(ctx)
  glow(ctx, CGPoint(x: 256, y: 256), 240, c(accent, 0.18))
  let o = CGPoint(x: 256, y: 256), r: CGFloat = 170
  let pts = (0..<6).map { i -> CGPoint in
    let a = CGFloat(i) * .pi / 3 - .pi / 2
    return CGPoint(x: o.x + r * cos(a), y: o.y + r * sin(a))
  }
  ctx.saveGState(); ctx.setShadow(offset: CGSize(width: 0, height: 14), blur: 30, color: c(0x000000, 0.55))
  ctx.addPath(path(pts)); ctx.setFillColor(c(0x0B6B40)); ctx.fillPath(); ctx.restoreGState()
  let shades: [(UInt32, UInt32)] = [(0xC4FFDD, 0x6AF0AC), (0x8CFFC0, 0x35D488), (0x2FD483, 0x0E7F4C),
                                    (0x17A866, 0x0B6B40), (0x1FB872, 0x0F8A52), (0x6CF5B0, 0x2BC57C)]
  let inner = (0..<6).map { i -> CGPoint in
    let a = CGFloat(i) * .pi / 3 - .pi / 2
    return CGPoint(x: o.x + r * 0.42 * cos(a), y: o.y + r * 0.42 * sin(a))
  }
  for i in 0..<6 {
    let f = path([pts[i], pts[(i + 1) % 6], inner[(i + 1) % 6], inner[i]])
    fill(ctx, f, shades[i].0, shades[i].1)
    ctx.addPath(f); ctx.setStrokeColor(c(0xCFFFE2, 0.35)); ctx.setLineWidth(2.2); ctx.strokePath()
  }
  let table = path(inner)
  fill(ctx, table, 0xD9FFEA, 0x5CF2A6)
  ctx.addPath(table); ctx.setStrokeColor(c(0xCFFFE2, 0.5)); ctx.setLineWidth(2.2); ctx.strokePath()
  beam(ctx, y: 256, from: 70, to: 442, width: 8)
}))

variations.append(("g_line_art", "Minimal line-art gem in a viewfinder", { ctx in
  darkBackground(ctx)
  glow(ctx, CGPoint(x: 256, y: 262), 200, c(accent, 0.14))
  ctx.saveGState(); ctx.setShadow(offset: .zero, blur: 14, color: c(accent, 0.7))
  gem(ctx, CGPoint(x: 256, y: 267), 0.95, outline: accent, outlineAlpha: 1, strokeOnly: true, strokeWidth: 10)
  ctx.restoreGState()
  // Viewfinder: rounded square broken at the middle of each side.
  ctx.setStrokeColor(c(0xE9FFF2, 0.9)); ctx.setLineWidth(14); ctx.setLineCap(.round)
  let a: CGFloat = 84, b: CGFloat = 428, rr: CGFloat = 46, gapHalf: CGFloat = 62, m: CGFloat = 256
  for (cx, cy, sx, sy) in [(a, a, 1.0, 1.0), (b, a, -1.0, 1.0), (a, b, 1.0, -1.0), (b, b, -1.0, -1.0)] {
    ctx.move(to: CGPoint(x: cx, y: m - sy * gapHalf))
    ctx.addLine(to: CGPoint(x: cx, y: cy + sy * rr))
    ctx.addQuadCurve(to: CGPoint(x: cx + sx * rr, y: cy), control: CGPoint(x: cx, y: cy))
    ctx.addLine(to: CGPoint(x: m - sx * gapHalf, y: cy)); ctx.strokePath()
  }
}))

variations.append(("h_badge", "Badge with wordmark (splash / web)", { ctx in
  darkBackground(ctx)
  glow(ctx, CGPoint(x: 256, y: 222), 200, c(accent, 0.22))
  gem(ctx, CGPoint(x: 256, y: 222), 0.62)
  brackets(ctx, 132, 312, len: 42, width: 15, color: c(accent))
  // Brackets above are drawn around y 150..362; shift wordmark below.
  let word = NSAttributedString(string: "JadeScan", attributes: [
    .font: NSFont(name: "ChakraPetch-Bold", size: 64)!, .foregroundColor: NSColor(cgColor: c(0xF2FFF7))!, .kern: 1])
  let ws = word.size()
  word.draw(at: CGPoint(x: 256 - ws.width / 2, y: 340))
}))

// MARK: - Render
try! FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)
var icons: [(String, String, CGImage)] = []
for (name, label, draw) in variations {
  let img512 = canvas(512, 512) { draw($0) }
  let img1024 = canvas(1024, 1024) { ctx in ctx.scaleBy(x: 2, y: 2); draw(ctx) }
  save(img512, "\(outDir)/\(name)_512.png")
  save(img1024, "\(outDir)/\(name)_1024.png")
  icons.append((name, label, img512))
}

// Contact sheet: each icon with Play's rounded mask, plus a small launcher-size preview.
let cols = 4, cell: CGFloat = 300, pad: CGFloat = 36, labelH: CGFloat = 90
let rows = (icons.count + cols - 1) / cols
let W = Int(CGFloat(cols) * (cell + pad) + pad), H = Int(CGFloat(rows) * (cell + pad + labelH) + pad + 40)
let sheet = canvas(W, H) { ctx in
  ctx.setFillColor(c(0x101614)); ctx.fill(CGRect(x: 0, y: 0, width: W, height: H))
  for (i, icon) in icons.enumerated() {
    let x = pad + CGFloat(i % cols) * (cell + pad), y = pad + CGFloat(i / cols) * (cell + pad + labelH)
    let r = CGRect(x: x, y: y, width: cell, height: cell)
    ctx.saveGState(); ctx.addPath(CGPath(roundedRect: r, cornerWidth: cell * 0.2, cornerHeight: cell * 0.2, transform: nil)); ctx.clip()
    drawImage(ctx, icon.2, r); ctx.restoreGState()
    // 48 px launcher preview, bottom-right of the cell label row.
    let small = CGRect(x: x + cell - 48, y: y + cell + 12, width: 48, height: 48)
    ctx.saveGState(); ctx.addPath(CGPath(ellipseIn: small, transform: nil)); ctx.clip(); drawImage(ctx, icon.2, small); ctx.restoreGState()
    let letter = String(icon.0.prefix(1)).uppercased()
    NSAttributedString(string: "\(letter)  \(icon.1)", attributes: [
      .font: NSFont(name: "ChakraPetch-SemiBold", size: 15)!, .foregroundColor: NSColor(cgColor: c(0xD8EFE2))!])
      .draw(in: CGRect(x: x, y: y + cell + 10, width: cell - 60, height: 80))
  }
}
save(sheet, "\(outDir)/_contact_sheet.png")
print("wrote \(icons.count) variations to \(outDir)")
