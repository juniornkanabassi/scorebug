import AppKit
import SwiftUI

var checks = 0
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
