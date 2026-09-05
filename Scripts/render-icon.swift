// Renders the Scorebug app icon in the macOS Tahoe style: a squircle with a deep-blue to
// electric-blue vertical gradient, a soft top light, and a centred broadcast score bug glyph
// (two digit cells, a dash, and a clock plate). Usage: swift Scripts/render-icon.swift <iconset dir>
import AppKit

let out = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)

func squircle(in r: NSRect, radius: CGFloat) -> NSBezierPath { NSBezierPath(roundedRect: r, xRadius: radius, yRadius: radius) }

func roundedFont(size: CGFloat, weight: NSFont.Weight) -> NSFont {
    let base = NSFont.systemFont(ofSize: size, weight: weight)
    if let rounded = base.fontDescriptor.withDesign(.rounded) {
        return NSFont(descriptor: rounded, size: size) ?? base
    }
    return base
}

func text(_ t: String, cx: CGFloat, cy: CGFloat, color: NSColor, font: NSFont) {
    let str = NSAttributedString(string: t, attributes: [.font: font, .foregroundColor: color])
    let sz = str.size()
    str.draw(at: NSPoint(x: cx - sz.width / 2, y: cy - sz.height / 2))
}

func render(_ size: CGFloat) -> NSImage {
    let img = NSImage(size: NSSize(width: size, height: size))
    img.lockFocus()
    let s = size / 1024
    let ctx = NSGraphicsContext.current!.cgContext

    // squircle tile: macOS Tahoe grid, ~100px inset / 224px corner radius at 1024
    let inset = 100 * s
    let tileRect = NSRect(x: inset, y: inset, width: size - 2 * inset, height: size - 2 * inset)
    let tile = squircle(in: tileRect, radius: 224 * s)

    let deepBlue = NSColor(red: 0x0B / 255.0, green: 0x1A / 255.0, blue: 0x5C / 255.0, alpha: 1)
    let electricBlue = NSColor(red: 0x2F / 255.0, green: 0x5B / 255.0, blue: 0xFF / 255.0, alpha: 1)

    // shadow behind the tile
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -14 * s), blur: 40 * s, color: NSColor.black.withAlphaComponent(0.35).cgColor)
    deepBlue.setFill(); tile.fill()
    ctx.restoreGState()

    // gradient body: electric blue at top, deep blue at bottom, straight vertical
    ctx.saveGState(); tile.addClip()
    NSGradient(colors: [deepBlue, electricBlue])!.draw(in: tileRect, angle: 90)
    // very soft top light, no clutter, no pitch lines
    let sweep = NSGradient(colors: [NSColor.white.withAlphaComponent(0.0), NSColor.white.withAlphaComponent(0.16)])!
    sweep.draw(in: NSRect(x: tileRect.minX, y: tileRect.minY + tileRect.height * 0.45, width: tileRect.width, height: tileRect.height * 0.55), angle: 90)
    ctx.restoreGState()

    // the score bug glyph
    let tiny = size <= 32
    let barW = size * 0.68
    let barH = size * 0.19
    let barX = (size - barW) / 2
    let barRadius = 36 * s

    let clockW = barW * 0.42
    let clockH = size * 0.082
    let overlap = size * 0.008
    let shiftUp = size * 0.03

    let barY: CGFloat
    if tiny {
        barY = size / 2 - barH / 2
    } else {
        let span = barH + clockH - overlap
        let barTop = size * 0.5 + shiftUp + span / 2
        barY = barTop - barH
    }

    let bar = squircle(in: NSRect(x: barX, y: barY, width: barW, height: barH), radius: barRadius)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -6 * s), blur: 28 * s, color: NSColor.black.withAlphaComponent(0.25).cgColor)
    NSColor.white.setFill(); bar.fill()
    ctx.restoreGState()

    // subtle 1px inner shadow along the bar's top inner edge
    ctx.saveGState(); bar.addClip()
    let innerShadow = NSGradient(colors: [NSColor.black.withAlphaComponent(0.10), NSColor.black.withAlphaComponent(0.0)])!
    innerShadow.draw(in: NSRect(x: barX, y: barY + barH - barH * 0.22, width: barW, height: barH * 0.22), angle: -90)
    ctx.restoreGState()

    let cellW = barW * 0.24
    let cellH = barH * 0.68
    let cellY = barY + barH * 0.16
    let homeCell = squircle(in: NSRect(x: barX + barW * 0.06, y: cellY, width: cellW, height: cellH), radius: 18 * s)
    let awayCell = squircle(in: NSRect(x: barX + barW - barW * 0.06 - cellW, y: cellY, width: cellW, height: cellH), radius: 18 * s)
    deepBlue.setFill(); homeCell.fill()
    NSColor(red: 0.93, green: 0.20, blue: 0.24, alpha: 1).setFill(); awayCell.fill()

    let digitFont = roundedFont(size: cellH * 0.60, weight: .black)
    text("2", cx: homeCell.bounds.midX, cy: homeCell.bounds.midY, color: .white, font: digitFont)
    text("1", cx: awayCell.bounds.midX, cy: awayCell.bounds.midY, color: .white, font: digitFont)

    if !tiny {
        // thin white dash between the cells, embossed with a soft shadow so it reads on the white bar
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: -1 * s), blur: 3 * s, color: NSColor.black.withAlphaComponent(0.22).cgColor)
        text("–", cx: size / 2, cy: barY + barH / 2, color: NSColor.white, font: roundedFont(size: barH * 0.34, weight: .semibold))
        ctx.restoreGState()

        // clock plate: white, tucked under the bar, overlapping its bottom edge by a few px.
        // Cast the drop shadow only below the bar so it doesn't smudge into the bar's white fill,
        // then lay a shadow-free fill on top so the overlapped seam stays clean.
        let clockX = (size - clockW) / 2
        let clockTop = barY + overlap
        let clockY = clockTop - clockH
        let clock = squircle(in: NSRect(x: clockX, y: clockY, width: clockW, height: clockH), radius: 18 * s)
        ctx.saveGState()
        NSBezierPath(rect: NSRect(x: 0, y: 0, width: size, height: barY)).addClip()
        ctx.setShadow(offset: CGSize(width: 0, height: -3 * s), blur: 10 * s, color: NSColor.black.withAlphaComponent(0.18).cgColor)
        NSColor.white.setFill(); clock.fill()
        ctx.restoreGState()
        NSColor.white.setFill(); clock.fill()
        text("90:00", cx: clock.bounds.midX, cy: clock.bounds.midY, color: NSColor(white: 0.08, alpha: 1), font: NSFont.monospacedDigitSystemFont(ofSize: clockH * 0.52, weight: .black))
    }

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
