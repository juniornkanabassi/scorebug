// Renders the Scorebug app icon: a squircle canvas with a calm pitch-green gradient ground,
// a dark navy scoreboard bar holding two separately-spaced white "0" digits (with a small
// scoreboard-style divider dash at larger sizes) flanked by a small red (home) and light-blue
// (away) team tile, and a flat white-and-navy football resting on the bar's top edge.
// Combines the two Flaticon reference concepts (navy board + pitch, and paired team tiles)
// into one Apple-style, single-highlight, flat-shape composition.
//
// Usage:
//   swift Scripts/render-icon.swift <iconset dir>              writes the full .iconset PNGs
//   swift Scripts/render-icon.swift --variants <output dir>    writes preview-1024-green.png
//                                                               and preview-1024-sky.png for
//                                                               side-by-side ground comparison
import AppKit

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

func textWidth(_ t: String, font: NSFont) -> CGFloat {
    NSAttributedString(string: t, attributes: [.font: font]).size().width
}

// A regular pentagon path, `rotation` in radians (0 = a vertex pointing straight up).
func pentagon(center: NSPoint, radius: CGFloat, rotation: CGFloat) -> NSBezierPath {
    let path = NSBezierPath()
    for i in 0..<5 {
        let angle = rotation + CGFloat(i) * (2 * .pi / 5) - .pi / 2
        let p = NSPoint(x: center.x + radius * cos(angle), y: center.y + radius * sin(angle))
        if i == 0 { path.move(to: p) } else { path.line(to: p) }
    }
    path.close()
    return path
}

// `bgStyle`: "green" (default, shipped) is a single-hue pitch-green ground; "sky" keeps the
// earlier green-to-sky-blue ground, produced only for a side-by-side comparison.
func render(_ size: CGFloat, bgStyle: String = "green") -> NSImage {
    let img = NSImage(size: NSSize(width: size, height: size))
    img.lockFocus()
    let s = size / 1024
    let ctx = NSGraphicsContext.current!.cgContext

    // squircle tile: macOS grid, ~100px inset / 224px corner radius at 1024
    let inset = 100 * s
    let tileRect = NSRect(x: inset, y: inset, width: size - 2 * inset, height: size - 2 * inset)
    let tile = squircle(in: tileRect, radius: 224 * s)

    // Palette.
    let skyTop = NSColor(red: 0x8A / 255.0, green: 0xC8 / 255.0, blue: 0xEE / 255.0, alpha: 1)
    let greenMid = NSColor(red: 0x3C / 255.0, green: 0x9A / 255.0, blue: 0x5E / 255.0, alpha: 1)
    let greenBottom = NSColor(red: 0x1F / 255.0, green: 0x6B / 255.0, blue: 0x3F / 255.0, alpha: 1)
    let greenTop = NSColor(red: 0x5F / 255.0, green: 0xBF / 255.0, blue: 0x7A / 255.0, alpha: 1)
    let navyTop = NSColor(red: 0x14 / 255.0, green: 0x1B / 255.0, blue: 0x3A / 255.0, alpha: 1)
    let navyBottom = NSColor(red: 0x0E / 255.0, green: 0x14 / 255.0, blue: 0x30 / 255.0, alpha: 1)
    let redTile = NSColor(red: 0xE8 / 255.0, green: 0x43 / 255.0, blue: 0x3D / 255.0, alpha: 1)
    let blueTile = NSColor(red: 0x29 / 255.0, green: 0xB6 / 255.0, blue: 0xF6 / 255.0, alpha: 1)

    // Background: flat, no shadow bleeding past the mask. A single hue family (deep pitch
    // green to a lighter fresh green) reads calmer and more Apple-like than a green-to-sky
    // band; the "sky" variant is kept only so the two can be compared side by side.
    ctx.saveGState(); tile.addClip()
    if bgStyle == "sky" {
        NSGradient(colors: [greenBottom, greenMid, skyTop], atLocations: [0, 0.45, 1], colorSpace: .deviceRGB)!
            .draw(in: tileRect, angle: 90)
    } else {
        NSGradient(colors: [greenBottom, greenTop])!.draw(in: tileRect, angle: 90)
    }
    ctx.restoreGState()

    // Scoreboard bar, middle third of the canvas.
    let barW = size * 0.66
    let barH = size * 0.30
    let barX = (size - barW) / 2
    let barY = size * 0.5 - barH / 2
    let barRadius = barH * 0.09
    let barRect = NSRect(x: barX, y: barY, width: barW, height: barH)
    let bar = squircle(in: barRect, radius: barRadius)

    // Shadow pass only (solid fill, discarded under the gradient repaint below) so the drop
    // shadow stays soft and contained without smudging the gradient's edges.
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -8 * s), blur: 24 * s, color: NSColor.black.withAlphaComponent(0.22).cgColor)
    navyBottom.setFill(); bar.fill()
    ctx.restoreGState()

    // Gradient repaint, crisp (no shadow), plus the icon's one permitted inner highlight.
    ctx.saveGState(); bar.addClip()
    NSGradient(colors: [navyBottom, navyTop])!.draw(in: barRect, angle: 90)
    let sheen = NSGradient(colors: [NSColor.white.withAlphaComponent(0.0), NSColor.white.withAlphaComponent(0.14)])!
    sheen.draw(in: NSRect(x: barX, y: barY + barH * 0.7, width: barW, height: barH * 0.3), angle: 90)
    ctx.restoreGState()

    // Small home/away team tiles, flanking the digits near the bar's edges.
    let tileMargin = barW * 0.06
    let tileW = barW * 0.09
    let tileH = barH * 0.46
    let tileY = barY + (barH - tileH) / 2
    let tileRadius = tileH * 0.28
    let home = squircle(in: NSRect(x: barX + tileMargin, y: tileY, width: tileW, height: tileH), radius: tileRadius)
    let away = squircle(in: NSRect(x: barX + barW - tileMargin - tileW, y: tileY, width: tileW, height: tileH), radius: tileRadius)
    redTile.setFill(); home.fill()
    blueTile.setFill(); away.fill()

    // The two large digits, showing the flat "0 – 0" opening score, drawn as two separately
    // positioned glyphs with a clear gap (not one touching "00"). A short scoreboard-style
    // divider dash sits in that gap at 128px and above; below that the dash is dropped but
    // the gap is kept. Skipped below 24px, where the glyphs would blur into noise.
    if size > 24 {
        let digitFont = roundedFont(size: barH * 0.60, weight: .black)
        let digitWidth = textWidth("0", font: digitFont)
        let gap = digitWidth * 0.35
        let midY = barY + barH / 2
        text("0", cx: size / 2 - gap / 2 - digitWidth / 2, cy: midY, color: .white, font: digitFont)
        text("0", cx: size / 2 + gap / 2 + digitWidth / 2, cy: midY, color: .white, font: digitFont)

        if size >= 128 {
            let dashWidth = gap * 0.55
            let dashHeight = max(size * 0.012, barH * 0.07)
            let dashRect = NSRect(x: size / 2 - dashWidth / 2, y: midY - dashHeight / 2, width: dashWidth, height: dashHeight)
            NSColor.white.setFill()
            squircle(in: dashRect, radius: dashHeight / 2).fill()
        }
    }

    // Football, resting on the bar's top edge: the centre sits just above the line so close
    // to 40% of the ball's height overlaps the bar, matching the reference concept of a ball
    // resting on the board rather than floating above it. Centred for a symmetric composition.
    let ballRadius = size * 0.155
    let boardTopY = barY + barH
    let overlapFraction: CGFloat = 0.40
    let ballCenter = NSPoint(x: size / 2, y: boardTopY + ballRadius * (1 - 2 * overlapFraction))
    let ballRect = NSRect(x: ballCenter.x - ballRadius, y: ballCenter.y - ballRadius, width: ballRadius * 2, height: ballRadius * 2)
    let ballPath = NSBezierPath(ovalIn: ballRect)
    NSColor.white.setFill(); ballPath.fill()

    // Pentagon pattern: one regular pentagon at the centre, five around the rim (each partly
    // clipped by the ball), connected to the centre pentagon by thin navy seams running
    // corner to corner. The ring sits 36 degrees off the centre pentagon's own rotation so
    // each centre-pentagon corner lines up radially with the facing corner of its ring
    // pentagon, which is what makes the seams run straight. Below 48px, only the centre
    // pentagon is drawn (plain white disc otherwise) to avoid noise at small sizes.
    let centerRadius = ballRadius * 0.38
    let ringRadius = ballRadius * 0.30
    let ringDistance = ballRadius * 0.62
    let centerRotation: CGFloat = .pi / 5 // 36 degrees, aligns centre-pentagon corners with the ring directions below

    ctx.saveGState(); ballPath.addClip()
    let centerPent = pentagon(center: ballCenter, radius: centerRadius, rotation: centerRotation)
    navyTop.setFill(); centerPent.fill()

    if size > 48 {
        for i in 0..<5 {
            let a = -CGFloat.pi / 2 + CGFloat(i) * (2 * .pi / 5) + .pi / 5
            let dir = NSPoint(x: cos(a), y: sin(a))
            let ringCenter = NSPoint(x: ballCenter.x + ringDistance * dir.x, y: ballCenter.y + ringDistance * dir.y)
            let ringRotation = a - .pi / 2
            let ringPent = pentagon(center: ringCenter, radius: ringRadius, rotation: ringRotation)
            navyTop.setFill(); ringPent.fill()

            let centerVertex = NSPoint(x: ballCenter.x + centerRadius * dir.x, y: ballCenter.y + centerRadius * dir.y)
            let ringVertex = NSPoint(x: ringCenter.x - ringRadius * dir.x, y: ringCenter.y - ringRadius * dir.y)
            let seam = NSBezierPath()
            seam.move(to: centerVertex)
            seam.line(to: ringVertex)
            seam.lineWidth = max(1, size * 0.006)
            navyTop.setStroke()
            seam.stroke()
        }
    }
    ctx.restoreGState()

    // A thin navy stroke separates the ball from the sky/pitch behind it.
    navyTop.setStroke()
    ballPath.lineWidth = size * 0.015
    ballPath.stroke()

    img.unlockFocus()
    return img
}

func writePNG(_ img: NSImage, px: Int, to url: URL) {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    img.draw(in: NSRect(x: 0, y: 0, width: px, height: px))
    NSGraphicsContext.restoreGraphicsState()
    try! rep.representation(using: .png, properties: [:])!.write(to: url)
}

let args = CommandLine.arguments

if args.count >= 3, args[1] == "--variants" {
    let vout = URL(fileURLWithPath: args[2], isDirectory: true)
    try? FileManager.default.createDirectory(at: vout, withIntermediateDirectories: true)
    for (name, style) in [("preview-1024-green", "green"), ("preview-1024-sky", "sky")] {
        writePNG(render(1024, bgStyle: style), px: 1024, to: vout.appendingPathComponent("\(name).png"))
    }
    print("variants written")
} else {
    let out = URL(fileURLWithPath: args[1], isDirectory: true)
    try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
    for (name, px) in [("icon_16x16", 16), ("icon_16x16@2x", 32), ("icon_32x32", 32), ("icon_32x32@2x", 64), ("icon_128x128", 128), ("icon_128x128@2x", 256), ("icon_256x256", 256), ("icon_256x256@2x", 512), ("icon_512x512", 512), ("icon_512x512@2x", 1024)] {
        writePNG(render(CGFloat(px)), px: px, to: out.appendingPathComponent("\(name).png"))
    }
    print("iconset written")
}
