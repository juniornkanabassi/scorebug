import SwiftUI

/// The focused match supplies the same actions to its controls and the menu bar.
struct MatchCommandContext {
    let slot: Int
    let homeName: String
    let awayName: String
    let clockRunning: Bool
    let clockEnabled: Bool
    let endPeriodEnabled: Bool
    let goalsEnabled: Bool
    let visible: Bool
    let previewVisible: Bool
    let goalHome: () -> Void
    let goalAway: () -> Void
    let playPause: () -> Void
    let endPeriod: () -> Void
    let toggleVisible: () -> Void
    let togglePreview: () -> Void
    let reset: () -> Void
}

private struct MatchCommandsKey: FocusedValueKey {
    typealias Value = MatchCommandContext
}

extension FocusedValues {
    var matchCommands: MatchCommandContext? {
        get { self[MatchCommandsKey.self] }
        set { self[MatchCommandsKey.self] = newValue }
    }
}
