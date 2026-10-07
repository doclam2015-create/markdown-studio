import AppKit

// Genera los íconos: mac (con margen y sombra) e ios (a sangre)
func render(size: CGFloat, mac: Bool) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size), bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let s = size / 1024
    let bgRect = mac ? NSRect(x: 100*s, y: 100*s, width: 824*s, height: 824*s) : NSRect(x: 0, y: 0, width: size, height: size)
    let bgPath = mac ? NSBezierPath(roundedRect: bgRect, xRadius: 185*s, yRadius: 185*s) : NSBezierPath(rect: bgRect)
    if mac {
        NSGraphicsContext.saveGraphicsState()
        let sh = NSShadow(); sh.shadowColor = NSColor.black.withAlphaComponent(0.35); sh.shadowOffset = NSSize(width: 0, height: -12*s); sh.shadowBlurRadius = 28*s; sh.set()
        NSColor.black.setFill(); bgPath.fill()
        NSGraphicsContext.restoreGraphicsState()
    }
    let grad = NSGradient(colors: [NSColor(srgbRed: 0.18, green: 0.42, blue: 0.87, alpha: 1), NSColor(srgbRed: 0.08, green: 0.19, blue: 0.35, alpha: 1)])!
    grad.draw(in: bgPath, angle: -90)
    // brillo superior
    let gl = NSGradient(colors: [NSColor.white.withAlphaComponent(0.16), NSColor.white.withAlphaComponent(0)])!
    gl.draw(in: bgPath, angle: -90)

    // hoja
    let k: CGFloat = mac ? 0.805 : 1.0
    let cx = size/2, cy = size/2
    func P(_ x: CGFloat, _ y: CGFloat) -> NSPoint { NSPoint(x: cx + (x-512)*s*k, y: cy - (y-512)*s*k) }
    let fold: CGFloat = 120
    let L: CGFloat = 262, R: CGFloat = 762, T: CGFloat = 190, B: CGFloat = 834, r: CGFloat = 46
    let page = NSBezierPath()
    page.move(to: P(L+r, T)); page.line(to: P(R-fold, T)); page.line(to: P(R, T+fold)); page.line(to: P(R, B-r))
    page.appendArc(from: P(R, B), to: P(R-r, B), radius: r*s*k)
    page.line(to: P(L+r, B)); page.appendArc(from: P(L, B), to: P(L, B-r), radius: r*s*k)
    page.line(to: P(L, T+r)); page.appendArc(from: P(L, T), to: P(L+r, T), radius: r*s*k); page.close()
    NSGraphicsContext.saveGraphicsState()
    let ps = NSShadow(); ps.shadowColor = NSColor.black.withAlphaComponent(0.30); ps.shadowOffset = NSSize(width: 0, height: -14*s*k); ps.shadowBlurRadius = 34*s*k; ps.set()
    NSColor.white.setFill(); page.fill()
    NSGraphicsContext.restoreGraphicsState()
    let fp = NSBezierPath(); fp.move(to: P(R-fold, T)); fp.line(to: P(R-fold, T+fold-22)); fp.appendArc(from: P(R-fold, T+fold), to: P(R-fold+22, T+fold), radius: 22*s*k); fp.line(to: P(R, T+fold)); fp.close()
    NSColor(srgbRed: 0.79, green: 0.85, blue: 0.95, alpha: 1).setFill(); fp.fill()

    // marca M↓
    let navy = NSColor(srgbRed: 0.12, green: 0.31, blue: 0.55, alpha: 1)
    navy.setFill()
    let m = NSBezierPath()
    let mx: CGFloat = 318, my: CGFloat = 430, mw: CGFloat = 250, mh: CGFloat = 210, st: CGFloat = 54
    m.move(to: P(mx, my+mh)); m.line(to: P(mx, my)); m.line(to: P(mx+st, my)); m.line(to: P(mx+mw/2, my+92)); m.line(to: P(mx+mw-st, my))
    m.line(to: P(mx+mw, my)); m.line(to: P(mx+mw, my+mh)); m.line(to: P(mx+mw-st, my+mh)); m.line(to: P(mx+mw-st, my+86))
    m.line(to: P(mx+mw/2, my+170)); m.line(to: P(mx+st, my+86)); m.line(to: P(mx+st, my+mh)); m.close(); m.fill()
    let a = NSBezierPath()
    let ax: CGFloat = 640, aw: CGFloat = 50
    a.move(to: P(ax-aw/2, my)); a.line(to: P(ax+aw/2, my)); a.line(to: P(ax+aw/2, my+112)); a.line(to: P(ax+aw/2+44, my+112))
    a.line(to: P(ax, my+mh)); a.line(to: P(ax-aw/2-44, my+112)); a.line(to: P(ax-aw/2, my+112)); a.close(); a.fill()
    // renglones
    NSColor(srgbRed: 0.80, green: 0.85, blue: 0.91, alpha: 1).setFill()
    for (i, w) in [372, 300, 336].enumerated() {
        let y = CGFloat(700 + i*44)
        let p1 = P(318, y), p2 = P(318 + CGFloat(w), y + 20)
        NSBezierPath(roundedRect: NSRect(x: p1.x, y: p2.y, width: p2.x-p1.x, height: p1.y-p2.y), xRadius: 10*s*k, yRadius: 10*s*k).fill()
    }
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

let out = CommandLine.arguments[1]
try! render(size: 1024, mac: true).write(to: URL(fileURLWithPath: out + "/icon-mac-1024.png"))
try! render(size: 1024, mac: false).write(to: URL(fileURLWithPath: out + "/icon-ios-1024.png"))
