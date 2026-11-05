import AppKit
import SwiftUI

var checks = 0
let competitions = ["premier-league", "champions-league", "europa-league", "conference-league",
                    "nations-league", "ligue1", "la-liga", "serie-a", "bundesliga", "club-world-cup", "unknown"]
let samples: [Color] = competitions.map(CompetitionColours.colour)
    + [.black, .white, .yellow, .cyan, .gray, .green, .red]
for name in [NSAppearance.Name.aqua, .darkAqua] {
    NSAppearance(named: name)!.performAsCurrentDrawingAppearance {
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
print("PASS NativeStyleChecks: \(checks) light/dark foreground contrast checks")

let sections: [SidebarSection] = [.slot(1), .slot(2), .library]
for section in sections {
    precondition(SidebarSection(storageID: section.storageID) == section)
}
precondition(SidebarSection(storageID: "settings") == .slot(1))
precondition(SidebarSection(storageID: "unknown") == .slot(1))
let errors = [
    ("Could not save state: disk full", "Unable to Save Match"),
    ("Could not save library: denied", "Unable to Save Team Library"),
    ("Loaded library has unsaved updates; could not save library.", "Unable to Save Team Library"),
    ("Could not save settings: denied", "Unable to Save Settings"),
    ("Could not load state: unreadable", "Unable to Load Saved Data"),
    ("No new crests matched in logos.", "Unable to Import Crests"),
    ("Could not import the competition logo: denied", "Unable to Import Competition Logo"),
    ("No ESPN fixture matched Home v Away.", "Unable to Find Fixture"),
    ("Unexpected operation", "Unable to Complete Action")
]
for (message, title) in errors { precondition(ErrorPresentation.title(for: message) == title) }
print("PASS NativeNavigationChecks: 5 restored selection and 9 error-title checks")
