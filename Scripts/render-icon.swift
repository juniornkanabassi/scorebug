// Renders the Scorebug app icon in the current macOS style: a squircle with a deep blue gradient, a soft light sweep,
// and a white score bug glyph with two digits and a green live clock strip. Usage: swift Scripts/render-icon.swift <iconset dir>
import AppKit

let out = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)

func squircle(in r: NSRect, radius: CGFloat) -> NSBezierPath { NSBezierPath(roundedRect: r, xRadius: radius, yRadius: radius) }

func render(_ size: CGFloat) -> NSImage {
    let img = NSImage(size: NSSize(width: size, height: size))
    img.lockFocus()
    let s = size / 1024
    let ctx = NSGraphicsContext.current!.cgContext
    let inset = 92 * s
    let tileRect = NSRect(x: inset, y: inset, width: size - 2 * inset, height: size - 2 * inset)
    let tile = squircle(in: tileRect, radius: 226 * s)
    // shadow
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -14 * s), blur: 40 * s, color: NSColor.black.withAlphaComponent(0.35).cgColor)
    NSColor(red: 0.05, green: 0.12, blue: 0.55, alpha: 1).setFill(); tile.fill()
    ctx.restoreGState()
    // gradient body
    ctx.saveGState(); tile.addClip()
    NSGradient(colors: [NSColor(red: 0.16, green: 0.36, blue: 1.0, alpha: 1), NSColor(red: 0.04, green: 0.10, blue: 0.48, alpha: 1)])!.draw(in: tileRect, angle: -70)
    // pitch lines, faint
    NSColor.white.withAlphaComponent(0.07).setStroke()
    let pitch = NSBezierPath(); pitch.lineWidth = 6 * s
    pitch.appendOval(in: NSRect(x: size * 0.36, y: size * 0.16, width: size * 0.28, height: size * 0.28))
    pitch.move(to: NSPoint(x: tileRect.minX, y: size * 0.30)); pitch.line(to: NSPoint(x: tileRect.maxX, y: size * 0.30))
    pitch.stroke()
    // light sweep
    let sweep = NSBezierPath(); sweep.move(to: NSPoint(x: tileRect.minX, y: tileRect.maxY)); sweep.line(to: NSPoint(x: tileRect.maxX, y: tileRect.maxY)); sweep.line(to: NSPoint(x: tileRect.maxX, y: tileRect.minY + tileRect.height * 0.55)); sweep.close()
    NSGradient(colors: [NSColor.white.withAlphaComponent(0.16), NSColor.white.withAlphaComponent(0.0)])!.draw(in: sweep, angle: -90)
    ctx.restoreGState()
    // the bug glyph: white rounded bar with two digit cells and a green clock strip beneath
    let barW = size * 0.62, barH = size * 0.20, barX = (size - barW) / 2, barY = size * 0.47
    let bar = squircle(in: NSRect(x: barX, y: barY, width: barW, height: barH), radius: 34 * s)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -8 * s), blur: 24 * s, color: NSColor.black.withAlphaComponent(0.25).cgColor)
    NSColor.white.setFill(); bar.fill()
    ctx.restoreGState()
    let cellW = barW * 0.24
    let homeCell = squircle(in: NSRect(x: barX + barW * 0.06, y: barY + barH * 0.16, width: cellW, height: barH * 0.68), radius: 18 * s)
    let awayCell = squircle(in: NSRect(x: barX + barW - barW * 0.06 - cellW, y: barY + barH * 0.16, width: cellW, height: barH * 0.68), radius: 18 * s)
    NSColor(red: 0.04, green: 0.10, blue: 0.48, alpha: 1).setFill(); homeCell.fill()
    NSColor(red: 0.93, green: 0.20, blue: 0.24, alpha: 1).setFill(); awayCell.fill()
    let font = NSFont.systemFont(ofSize: barH * 0.52, weight: .heavy)
    func text(_ t: String, cx: CGFloat, cy: CGFloat, color: NSColor, font: NSFont) {
        let str = NSAttributedString(string: t, attributes: [.font: font, .foregroundColor: color]); let sz = str.size()
        str.draw(at: NSPoint(x: cx - sz.width / 2, y: cy - sz.height / 2))
    }
    text("2", cx: homeCell.bounds.midX, cy: homeCell.bounds.midY, color: .white, font: font)
    text("1", cx: awayCell.bounds.midX, cy: awayCell.bounds.midY, color: .white, font: font)
    text("–", cx: size / 2, cy: barY + barH / 2, color: NSColor(white: 0.15, alpha: 1), font: NSFont.systemFont(ofSize: barH * 0.42, weight: .bold))
    let clock = squircle(in: NSRect(x: size * 0.34, y: barY - size * 0.115, width: size * 0.32, height: size * 0.085), radius: 22 * s)
    NSColor(red: 0.13, green: 0.80, blue: 0.45, alpha: 1).setFill(); clock.fill()
    text("90:00", cx: size / 2, cy: clock.bounds.midY, color: NSColor(red: 0.02, green: 0.16, blue: 0.10, alpha: 1), font: NSFont.monospacedDigitSystemFont(ofSize: size * 0.052, weight: .heavy))
    img.unlockFocus()
    return img
}

for (name, px) in [("icon_16x16", 16), ("icon_16x16@2x", 32), ("icon_32x32", 32), ("icon_32x32@2x", 64), ("icon_128x128", 128), ("icon_128x128@2x", 256), ("icon_256x256", 256), ("icon_256x256@2x", 512), ("icon_512x512", 512), ("icon_512x512@2x", 1024)] {
    let img = render(CGFloat(px))
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    img.draw(in: NSRect(x: 0, y: 0, width: px, height: px))
    NSGraphicsContext.restoreGraphicsState()
    try! rep.representation(using: .png, properties: [:])!.write(to: out.appendingPathComponent("\(name).png"))
}
print("iconset written")
