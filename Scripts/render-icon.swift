// Renders the Scorebug app icon: a charcoal tile with a small score bug (two club plates, white digits, a blue clock).
// Usage: swift Scripts/render-icon.swift Resources/AppIcon.iconset ; then iconutil -c icns Resources/AppIcon.iconset
import AppKit

let out = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)

func render(_ size: CGFloat) -> NSImage {
    let img = NSImage(size: NSSize(width: size, height: size))
    img.lockFocus()
    let s = size / 1024
    let ctx = NSGraphicsContext.current!.cgContext
    // Tile with macOS-style rounded corners and an inset.
    let inset = 100 * s
    let tile = NSBezierPath(roundedRect: NSRect(x: inset, y: inset, width: size - 2 * inset, height: size - 2 * inset), xRadius: 190 * s, yRadius: 190 * s)
    let grad = NSGradient(colors: [NSColor(red: 0.13, green: 0.12, blue: 0.18, alpha: 1), NSColor(red: 0.06, green: 0.05, blue: 0.09, alpha: 1)])!
    grad.draw(in: tile, angle: -90)
    // Bug plates
    let bugY = size * 0.44, bugH = size * 0.17
    let x0 = size * 0.20, w = size * 0.60
    let homeW = w * 0.31, scoreW = w * 0.14, clockW = w * 0.41 - w * 0.10
    func plate(_ x: CGFloat, _ width: CGFloat, _ color: NSColor, corners: (CGFloat, CGFloat)) {
        let p = NSBezierPath()
        let r = NSRect(x: x, y: bugY, width: width, height: bugH)
        p.appendRoundedRect(r, xRadius: 0, yRadius: 0)
        color.setFill(); p.fill()
    }
    ctx.saveGState()
    let clip = NSBezierPath(roundedRect: NSRect(x: x0, y: bugY, width: w, height: bugH), xRadius: 22 * s, yRadius: 22 * s)
    clip.addClip()
    plate(x0, homeW, NSColor(red: 0.0, green: 0.25, blue: 0.44, alpha: 1), corners: (1, 0))
    plate(x0 + homeW, scoreW, NSColor(red: 0.08, green: 0.08, blue: 0.1, alpha: 1), corners: (0, 0))
    plate(x0 + homeW + scoreW, scoreW, NSColor(red: 0.08, green: 0.08, blue: 0.1, alpha: 1), corners: (0, 0))
    plate(x0 + homeW + 2 * scoreW, w * 0.10, NSColor(red: 0.85, green: 0.16, blue: 0.11, alpha: 1), corners: (0, 0))
    plate(x0 + homeW + 2 * scoreW + w * 0.10, clockW, NSColor(red: 0.03, green: 0.37, blue: 1.0, alpha: 1), corners: (0, 1))
    ctx.restoreGState()
    // Digits
    let font = NSFont.systemFont(ofSize: bugH * 0.66, weight: .black)
    let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.white]
    func text(_ t: String, cx: CGFloat) {
        let str = NSAttributedString(string: t, attributes: attrs)
        let sz = str.size()
        str.draw(at: NSPoint(x: cx - sz.width / 2, y: bugY + (bugH - sz.height) / 2))
    }
    text("1", cx: x0 + homeW + scoreW / 2)
    text("0", cx: x0 + homeW + scoreW * 1.5)
    let clockFont = NSFont.monospacedDigitSystemFont(ofSize: bugH * 0.5, weight: .bold)
    let cstr = NSAttributedString(string: "90:00", attributes: [.font: clockFont, .foregroundColor: NSColor.white])
    let csz = cstr.size()
    cstr.draw(at: NSPoint(x: x0 + homeW + 2 * scoreW + w * 0.10 + (clockW - csz.width) / 2, y: bugY + (bugH - csz.height) / 2))
    // Orange accent bar under the bug, a nod to the control panel
    let bar = NSBezierPath(roundedRect: NSRect(x: x0, y: bugY - size * 0.06, width: w * 0.34, height: size * 0.028), xRadius: 8 * s, yRadius: 8 * s)
    NSGradient(colors: [NSColor(red: 1, green: 0.48, blue: 0.1, alpha: 1), NSColor(red: 1, green: 0.31, blue: 0.16, alpha: 1)])!.draw(in: bar, angle: 0)
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
