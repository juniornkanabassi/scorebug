import SwiftUI

/// Commands follow the focused scene, so Settings and other windows cannot control a hidden match.
struct MatchCommands: Commands {
    @FocusedValue(\.matchCommands) private var match

    var body: some Commands {
        CommandMenu("Match") {
            Button("Goal for Home") { match?.goalHome() }
                .keyboardShortcut("h", modifiers: [.command, .shift])
                .disabled(match?.goalsEnabled != true)
            Button("Goal for Away") { match?.goalAway() }
                .keyboardShortcut("a", modifiers: [.command, .shift])
                .disabled(match?.goalsEnabled != true)
            Divider()
            Button(match?.clockRunning == true ? "Pause Clock" : "Play Clock") { match?.playPause() }
                .keyboardShortcut(.space, modifiers: [])
                .disabled(match?.clockEnabled != true)
            Button("End Period") { match?.endPeriod() }
                .keyboardShortcut("e", modifiers: [.command, .shift])
                .disabled(match?.endPeriodEnabled != true)
            Divider()
            Button(match?.visible == true ? "Hide Bug" : "Show Bug") { match?.toggleVisible() }
                .keyboardShortcut("b", modifiers: [.command, .shift])
                .disabled(match == nil)
            Button("Reset Match…") { match?.reset() }
                .keyboardShortcut("r", modifiers: [.command, .shift])
                .disabled(match == nil)
        }
        CommandGroup(after: .toolbar) {
            Button(match?.previewVisible == true ? "Hide Preview" : "Show Preview") { match?.togglePreview() }
                .keyboardShortcut("p", modifiers: [.command, .shift])
                .disabled(match == nil)
        }
    }
}

struct LibraryCommands: Commands {
    @FocusedValue(\.libraryCommands) private var library

    var body: some Commands {
        CommandGroup(after: .toolbar) {
            Button("as List") { library?.setMode(.list) }
                .keyboardShortcut("1", modifiers: .command)
                .disabled(library == nil)
            Button("as Icons") { library?.setMode(.icons) }
                .keyboardShortcut("2", modifiers: .command)
                .disabled(library == nil)
        }
    }
}
