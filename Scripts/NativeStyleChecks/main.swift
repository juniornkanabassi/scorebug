import AppKit
import SwiftUI

var checks = 0
var shootoutChecks = 0

func blend(_ top: NSColor, over bottom: NSColor) -> NSColor {
    let a = top.alphaComponent
    return NSColor(srgbRed: top.redComponent * a + bottom.redComponent * (1 - a),
                   green: top.greenComponent * a + bottom.greenComponent * (1 - a),
                   blue: top.blueComponent * a + bottom.blueComponent * (1 - a), alpha: 1)
}

func luminance(_ colour: NSColor) -> Double { Surface.relativeLuminance(of: Color(nsColor: colour)) }

func contrast(_ a: NSColor, _ b: NSColor) -> Double {
    let (x, y) = (luminance(a), luminance(b))
    return (max(x, y) + 0.05) / (min(x, y) + 0.05)
}
let competitions = ["premier-league", "champions-league", "europa-league", "conference-league",
                    "nations-league", "ligue1", "la-liga", "serie-a", "bundesliga", "club-world-cup", "unknown"]
let samples: [Color] = competitions.map(CompetitionColours.colour)
    + [.black, .white, .yellow, .cyan, .gray, .green, .red]
for name in [NSAppearance.Name.aqua, .darkAqua] {
    NSAppearance(named: name)!.performAsCurrentDrawingAppearance {
        let panel = Surface.relativeLuminance(of: Surface.subtleFill)
        let label = Surface.relativeLuminance(of: Color(nsColor: .labelColor))
        let panelContrast = (max(panel, label) + 0.05) / (min(panel, label) + 0.05)
        precondition(panelContrast >= 4.5, "Panel heading lacks contrast in \(name.rawValue): \(panelContrast)")
        precondition(abs(panel - Surface.relativeLuminance(of: Color(nsColor: .controlBackgroundColor))) < 0.001,
                     "Match panels must use the control surface, not the under-page background")
        let outline = Surface.relativeLuminance(of: Surface.controlOutline)
        let outlineContrast = (max(panel, outline) + 0.05) / (min(panel, outline) + 0.05)
        precondition(outlineContrast >= 3, "Neutral goal button outline lacks contrast in \(name.rawValue): \(outlineContrast)")
        for fill in [Surface.statusSuccess, Surface.statusDanger, Color.accentColor] {
            let background = Surface.relativeLuminance(of: fill)
            let foreground = Surface.relativeLuminance(of: Surface.text(on: fill))
            let contrast = (max(background, foreground) + 0.05) / (min(background, foreground) + 0.05)
            precondition(contrast >= 4.5, "Shootout action text lacks contrast in \(name.rawValue): \(contrast)")
        }
        // B19: the shootout buttons are a faint tint over the panel, with primary text that stays readable both
        // enabled (4.5:1) and at the shared disabled opacity (2:1 and above the system's own disabled text).
        precondition(Surface.tintFillOpacity <= 0.25, "Shootout fill is no longer translucent")
        let panelColour = NSColor(Surface.subtleFill).usingColorSpace(.sRGB)!
        for tint in [Surface.statusSuccess, Surface.statusDanger] {
            let fill = blend(NSColor(Surface.tintFill(tint)).usingColorSpace(.sRGB)!, over: panelColour)
            let text = blend(NSColor.labelColor.usingColorSpace(.sRGB)!, over: fill)
            // The whole button at the shared disabled opacity: label and fill both fade towards the panel.
            let dimmedText = blend(text.withAlphaComponent(Surface.disabledOpacity), over: panelColour)
            let dimmedFill = blend(fill.withAlphaComponent(Surface.disabledOpacity), over: panelColour)
            let system = contrast(blend(NSColor.disabledControlTextColor.usingColorSpace(.sRGB)!, over: panelColour), panelColour)
            precondition(contrast(text, fill) >= 4.5, "Shootout label lacks contrast in \(name.rawValue): \(contrast(text, fill))")
            precondition(contrast(dimmedText, dimmedFill) >= 2 && contrast(dimmedText, dimmedFill) > system,
                         "Disabled shootout label unreadable in \(name.rawValue): \(contrast(dimmedText, dimmedFill)) against the system's \(system)")
            shootoutChecks += 2
        }
        // N5: the Off air badge reads against the preview pane and the black preview canvas (3:1), its text on it (4.5:1).
        let badge = blend(NSColor(Surface.stageBadge).usingColorSpace(.sRGB)!, over: NSColor(Surface.fill).usingColorSpace(.sRGB)!)
        for pane in [NSColor(Surface.fill).usingColorSpace(.sRGB)!, NSColor.black.usingColorSpace(.sRGB)!] {
            precondition(contrast(badge, blend(NSColor(Surface.fill).usingColorSpace(.sRGB)!, over: pane)) >= 4.5, "Off air text lacks contrast in \(name.rawValue)")
        }
        precondition(contrast(badge, NSColor(Surface.fill).usingColorSpace(.sRGB)!) >= 3, "Off air badge lacks contrast against the pane in \(name.rawValue)")
        shootoutChecks += 2
        for fill in samples {
            let luminance = Surface.relativeLuminance(of: fill)
            let foreground = Surface.relativeLuminance(of: Surface.text(on: fill))
            let contrast = (max(luminance, foreground) + 0.05) / (min(luminance, foreground) + 0.05)
            precondition(contrast >= 4.5, "Unreadable foreground in \(name.rawValue): \(contrast)")
            let blackContrast = (luminance + 0.05) / 0.05
            let whiteContrast = 1.05 / (luminance + 0.05)
            precondition(abs(contrast - max(blackContrast, whiteContrast)) < 0.01,
                         "Foreground does not maximise contrast")
            checks += 1
        }
    }
}
print("PASS NativeActionChecks: 2 neutral outline and 6 filled action text contrast checks")
print("PASS NativeShootoutChecks: \(shootoutChecks) translucent fill, disabled-label and Off air badge contrast checks")
print("PASS NativePanelChecks: 2 appearance contrast and semantic surface checks")
print("PASS NativeStyleChecks: \(checks) light/dark foreground contrast checks")

let sections: [SidebarSection] = [.slot(1), .slot(2), .library]
for section in sections {
    precondition(SidebarSection(storageID: section.storageID) == section)
}
precondition(SidebarSection(storageID: "settings") == .slot(1))
precondition(SidebarSection(storageID: "unknown") == .slot(1))
print("PASS NativeNavigationChecks: 5 restored selection checks")

precondition(Surface.relativeLuminance(of: CompetitionColours.colour(for: "premier-league"))
             == Surface.relativeLuminance(of: Color(hex: "#37003C")), "competition colours use Color(hex:)")

// Match commands: only the key main window acts, and the menu's play key needs its modifiers.
_ = NSApplication.shared
let mainWindow = NSWindow(contentRect: .init(x: 0, y: 0, width: 10, height: 10), styleMask: [.titled], backing: .buffered, defer: true)
let popover = NSPanel(contentRect: .init(x: 0, y: 0, width: 10, height: 10), styleMask: [.titled], backing: .buffered, defer: true)
precondition(MatchCommandGate.allows(key: mainWindow, main: mainWindow))
precondition(!MatchCommandGate.allows(key: popover, main: mainWindow), "popover or sheet key window drives the match")
precondition(!MatchCommandGate.allows(key: nil, main: mainWindow))
precondition(!MatchCommandGate.allows(key: mainWindow, main: nil))
final class Hit: NSObject { var count = 0; @objc func fire(_ sender: Any?) { count += 1 } }
let hit = Hit()
let menu = NSMenu()
let item = NSMenuItem(title: "Play Clock", action: #selector(Hit.fire(_:)), keyEquivalent: String(MatchCommandGate.playPauseKey.character))
item.target = hit
var mask: NSEvent.ModifierFlags = []
if MatchCommandGate.playPauseModifiers.contains(.command) { mask.insert(.command) }
if MatchCommandGate.playPauseModifiers.contains(.shift) { mask.insert(.shift) }
if MatchCommandGate.playPauseModifiers.contains(.option) { mask.insert(.option) }
if MatchCommandGate.playPauseModifiers.contains(.control) { mask.insert(.control) }
item.keyEquivalentModifierMask = mask
menu.addItem(item)
func space(_ flags: NSEvent.ModifierFlags) -> NSEvent {
    NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 0, windowNumber: 0, context: nil,
                     characters: " ", charactersIgnoringModifiers: " ", isARepeat: false, keyCode: 49)!
}
precondition(!mask.isEmpty && !menu.performKeyEquivalent(with: space([])) && hit.count == 0, "bare Space reaches the menu")
precondition(menu.performKeyEquivalent(with: space(mask)) && hit.count == 1, "modified Space misses Play Clock")
print("PASS NativeCommandChecks: 1 colour, 4 key-window and 2 menu key-equivalent checks")

// Identical menu inputs must not reuse another window's prompt/reset state.
func context(owner: UUID, slot: Int = 1) -> MatchCommandContext {
    MatchCommandContext(ownerID: owner, slot: slot, homeName: "Home", awayName: "Away",
                        clockRunning: false, clockEnabled: true, endPeriodEnabled: true,
                        goalsEnabled: true, visible: true, previewVisible: true,
                        goalHome: {}, goalAway: {}, playPause: {}, endPeriod: {},
                        toggleVisible: {}, togglePreview: {}, reset: {})
}
let owner = UUID()
precondition(context(owner: owner) == context(owner: owner))
precondition(context(owner: owner) != context(owner: UUID()), "same-slot windows must keep separate actions")
precondition(context(owner: owner) != context(owner: owner, slot: 2))
print("PASS NativeContextChecks: 3 window and slot identity checks")
