import AppKit

// Draws the Contacter icon in the house style (Uberdoer/Ubercal): dark navy squircle, glossy stacked blue cards.
// Two duplicate cards fan out behind a contact card; a glowing cyan-green badge merges them. Usage: make-icon <out.png>
let size: CGFloat = 1024
let rgb = CGColorSpaceCreateDeviceRGB()
let ctx = CGContext(data: nil, width: Int(size), height: Int(size), bitsPerComponent: 8, bytesPerRow: 0,
                    space: rgb, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!

func color(_ hex: UInt32, _ a: CGFloat = 1) -> CGColor {
    CGColor(red: CGFloat(hex >> 16 & 0xff) / 255, green: CGFloat(hex >> 8 & 0xff) / 255, blue: CGFloat(hex & 0xff) / 255, alpha: a)
}
func gradient(_ c: [CGColor]) -> CGGradient { CGGradient(colorsSpace: rgb, colors: c as CFArray, locations: nil)! }
func rounded(_ r: CGRect, _ radius: CGFloat) -> CGPath { CGPath(roundedRect: r, cornerWidth: radius, cornerHeight: radius, transform: nil) }
func fill(_ path: CGPath, _ g: CGGradient, from: CGPoint, to: CGPoint) {
    ctx.saveGState(); ctx.addPath(path); ctx.clip()
    ctx.drawLinearGradient(g, start: from, end: to, options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
    ctx.restoreGState()
}
func rotated(around r: CGRect, _ angle: CGFloat, _ body: () -> Void) {
    ctx.saveGState()
    ctx.translateBy(x: r.midX, y: r.midY); ctx.rotate(by: angle); ctx.translateBy(x: -r.midX, y: -r.midY)
    body()
    ctx.restoreGState()
}

// Background squircle with a blue rim glow.
let bgRect = CGRect(x: 0, y: 0, width: size, height: size).insetBy(dx: 36, dy: 36)
let bg = rounded(bgRect, 210)
fill(bg, gradient([color(0x0E1A3A), color(0x060B1C)]), from: CGPoint(x: 0, y: size), to: CGPoint(x: size, y: 0))
ctx.saveGState(); ctx.addPath(bg); ctx.clip()
ctx.setShadow(offset: .zero, blur: 60, color: color(0x2F6BFF, 0.9))
ctx.setStrokeColor(color(0x3B7BFF, 0.75)); ctx.setLineWidth(10)
ctx.addPath(bg); ctx.strokePath()
ctx.restoreGState()

/// A card is a slab: a darker copy below for thickness, a glow, then the gradient face.
func card(_ r: CGRect, angle: CGFloat, top: UInt32, bottom: UInt32, edge: UInt32) {
    rotated(around: r, angle) {
        let face = rounded(r, 64)
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: -10), blur: 50, color: color(0x2A5CFF, 0.8))
        ctx.addPath(rounded(r.offsetBy(dx: 0, dy: -22), 64)); ctx.setFillColor(color(edge)); ctx.fillPath()
        ctx.restoreGState()
        fill(face, gradient([color(top), color(bottom)]), from: CGPoint(x: r.minX, y: r.maxY), to: CGPoint(x: r.maxX, y: r.minY))
        ctx.saveGState(); ctx.addPath(face); ctx.setStrokeColor(color(0xFFFFFF, 0.28)); ctx.setLineWidth(5); ctx.strokePath(); ctx.restoreGState()
    }
}

// The two duplicates, fanned left and right.
card(CGRect(x: 170, y: 250, width: 620, height: 440), angle: 0.16, top: 0x3348F0, bottom: 0x3A22C8, edge: 0x1B1590)
card(CGRect(x: 234, y: 250, width: 620, height: 440), angle: -0.12, top: 0x2F6BFF, bottom: 0x2C3BE0, edge: 0x1A2AA8)

// Top card: the contact.
let page = CGRect(x: 190, y: 300, width: 644, height: 450)
rotated(around: page, 0.02) {
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -14), blur: 60, color: color(0x2A6CFF, 0.9))
    ctx.addPath(rounded(page.offsetBy(dx: 0, dy: -24), 64)); ctx.setFillColor(color(0x1C4FD8)); ctx.fillPath()
    ctx.restoreGState()
    let face = rounded(page, 64)
    fill(face, gradient([color(0x46B4FF), color(0x2E7CFF), color(0x2B55F0)]),
         from: CGPoint(x: page.minX, y: page.maxY), to: CGPoint(x: page.maxX, y: page.minY))
    ctx.addPath(face); ctx.setStrokeColor(color(0xFFFFFF, 0.35)); ctx.setLineWidth(5); ctx.strokePath()

    // Avatar: a white disc with a person silhouette.
    let avatar = CGRect(x: page.minX + 60, y: page.midY - 115, width: 230, height: 230)
    ctx.saveGState(); ctx.setShadow(offset: CGSize(width: 0, height: -6), blur: 20, color: color(0x0A1E6E, 0.5))
    fill(CGPath(ellipseIn: avatar, transform: nil), gradient([color(0xFFFFFF), color(0xCFE2FF)]),
         from: CGPoint(x: avatar.minX, y: avatar.maxY), to: CGPoint(x: avatar.maxX, y: avatar.minY))
    ctx.restoreGState()
    ctx.saveGState(); ctx.addEllipse(in: avatar); ctx.clip()
    let person = gradient([color(0x3C8DFF), color(0x2B55F0)])
    let head = CGRect(x: avatar.midX - 48, y: avatar.midY - 8, width: 96, height: 96)
    fill(CGPath(ellipseIn: head, transform: nil), person, from: CGPoint(x: head.minX, y: head.maxY), to: CGPoint(x: head.maxX, y: head.minY))
    let body = CGRect(x: avatar.midX - 92, y: avatar.minY - 70, width: 184, height: 170)
    fill(CGPath(ellipseIn: body, transform: nil), person, from: CGPoint(x: body.minX, y: body.maxY), to: CGPoint(x: body.maxX, y: body.minY))
    ctx.restoreGState()

    // Text lines: name (bold) and details.
    let lineX = avatar.maxX + 44
    for (i, (width, alpha, height)) in [(250.0, 0.9, 44.0), (200.0, 0.4, 28.0), (170.0, 0.4, 28.0)].enumerated() {
        let y = page.midY + 50 - CGFloat(i) * 78 - (i == 0 ? 0 : 10)
        ctx.addPath(rounded(CGRect(x: lineX, y: y, width: width, height: height), height / 2))
        ctx.setFillColor(color(0xFFFFFF, alpha)); ctx.fillPath()
    }
}

// Merge badge: glowing cyan-green disc with two strokes joining into one arrow.
let badge = CGRect(x: 650, y: 150, width: 250, height: 250)
ctx.saveGState(); ctx.setShadow(offset: .zero, blur: 60, color: color(0x5CFFC8, 0.9))
fill(CGPath(ellipseIn: badge, transform: nil), gradient([color(0xB8FFF0), color(0x3BE6B0), color(0x22C4E8)]),
     from: CGPoint(x: badge.minX, y: badge.maxY), to: CGPoint(x: badge.maxX, y: badge.minY))
ctx.restoreGState()
ctx.addEllipse(in: badge); ctx.setStrokeColor(color(0xFFFFFF, 0.75)); ctx.setLineWidth(6); ctx.strokePath()

let merge = CGMutablePath()
let cx = badge.midX, cy = badge.midY
merge.move(to: CGPoint(x: cx - 62, y: cy + 62)); merge.addQuadCurve(to: CGPoint(x: cx, y: cy - 6), control: CGPoint(x: cx - 4, y: cy + 50))
merge.move(to: CGPoint(x: cx + 62, y: cy + 62)); merge.addQuadCurve(to: CGPoint(x: cx, y: cy - 6), control: CGPoint(x: cx + 4, y: cy + 50))
merge.move(to: CGPoint(x: cx, y: cy - 6)); merge.addLine(to: CGPoint(x: cx, y: cy - 66))
merge.move(to: CGPoint(x: cx - 36, y: cy - 34)); merge.addLine(to: CGPoint(x: cx, y: cy - 70)); merge.addLine(to: CGPoint(x: cx + 36, y: cy - 34))
ctx.addPath(merge)
ctx.setStrokeColor(color(0x0B3B4A)); ctx.setLineWidth(22); ctx.setLineCap(.round); ctx.setLineJoin(.round)
ctx.strokePath()

let rep = NSBitmapImageRep(cgImage: ctx.makeImage()!)
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
