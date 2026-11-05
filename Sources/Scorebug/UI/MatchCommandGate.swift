import SwiftUI
import AppKit

enum MatchCommandGate {
    static let playPauseKey = KeyEquivalent.space
    static let playPauseModifiers: EventModifiers = [.command, .shift]

    /// A match command acts only while the match window itself is key. A popover or sheet (scorer search, club
    /// picker, Load fixture) is a separate key window that cannot become main, so typing there never drives the match.
    static func allows(key: NSWindow?, main: NSWindow?) -> Bool {
        guard let key else { return false }
        return key === main && key.attachedSheet == nil
    }
}
