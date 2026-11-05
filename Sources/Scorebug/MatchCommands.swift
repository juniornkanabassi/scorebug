import SwiftUI
import AppKit

/// Commands follow the focused scene, so Settings and other windows cannot control a hidden match.
struct MatchCommands: Commands {
    @FocusedValue(\.matchCommands) private var match

    var body: some Commands {
        CommandMenu("Match") {
            Button("Goal for \(match?.homeName ?? "Home")") { perform { $0.goalHome() } }
                .keyboardShortcut("h", modifiers: [.command, .shift])
                .disabled(match?.goalsEnabled != true)
            Button("Goal for \(match?.awayName ?? "Away")") { perform { $0.goalAway() } }
                .keyboardShortcut("a", modifiers: [.command, .shift])
                .disabled(match?.goalsEnabled != true)
            Divider()
            // Modified, because menu equivalents run before a focused text field gets the key. Bare Space stays
            // on the live bar's own Play button, inside the main window only.
            Button(match?.clockRunning == true ? "Pause Clock" : "Play Clock") { perform { $0.playPause() } }
                .keyboardShortcut(MatchCommandGate.playPauseKey, modifiers: MatchCommandGate.playPauseModifiers)
                .disabled(match?.clockEnabled != true)
            Button("End Period") { perform { $0.endPeriod() } }
                .keyboardShortcut("e", modifiers: [.command, .shift])
                .disabled(match?.endPeriodEnabled != true)
            Divider()
            Button(match?.visible == true ? "Hide Bug" : "Show Bug") { perform { $0.toggleVisible() } }
                .keyboardShortcut("b", modifiers: [.command, .shift])
                .disabled(match == nil)
            Button("Reset Match…") { perform { $0.reset() } }
                .keyboardShortcut("r", modifiers: [.command, .shift])
                .disabled(match == nil)
        }
        CommandGroup(after: .toolbar) {
            Button(match?.previewVisible == true ? "Hide Preview" : "Show Preview") { perform { $0.togglePreview() } }
                .keyboardShortcut("p", modifiers: [.command, .shift])
                .disabled(match == nil)
        }
    }

    private func perform(_ action: (MatchCommandContext) -> Void) {
        guard let match, MatchCommandGate.allows(key: NSApp.keyWindow, main: NSApp.mainWindow) else { return }
        action(match)
    }
}

struct LibraryCommands: Commands {
    @FocusedValue(\.libraryCommands) private var library

    var body: some Commands {
        CommandGroup(after: .toolbar) {
            Toggle("as List", isOn: Binding(get: { library?.isGrid == false }, set: { _ in library?.setMode(.list) }))
                .keyboardShortcut("1", modifiers: .command)
                .disabled(library == nil)
            Toggle("as Icons", isOn: Binding(get: { library?.isGrid == true }, set: { _ in library?.setMode(.icons) }))
                .keyboardShortcut("2", modifiers: .command)
                .disabled(library == nil)
        }
    }
}
