import SwiftUI

/// The focused match supplies the same actions to its controls and the menu bar.
/// Compare the owning view lifetime as well as menu inputs, because separate windows have separate prompt state.
struct MatchCommandContext: Equatable {
    let ownerID: UUID
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

    static func == (l: Self, r: Self) -> Bool {
        l.ownerID == r.ownerID && l.slot == r.slot && l.homeName == r.homeName && l.awayName == r.awayName && l.clockRunning == r.clockRunning
            && l.clockEnabled == r.clockEnabled && l.endPeriodEnabled == r.endPeriodEnabled && l.goalsEnabled == r.goalsEnabled
            && l.visible == r.visible && l.previewVisible == r.previewVisible
    }
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
