// Display derivation from the master clock: runOn and freezeAndCount. Mirrored in Overlays/overlay.js.
import Foundation

public enum ClockStyle: String, Codable, Sendable {
    /// Main clock keeps counting past the period end; "+N" sits beside it once added time is announced.
    case runOn
    /// Main clock stops at the period end; once added time is announced a second counter shows time since the end.
    case freezeAndCount
}

public struct ClockDisplay: Equatable, Sendable {
    public var main: String
    public var added: String?
    public var addedCounter: String?
    public var state: String?
    public var running: Bool
    /// True once a live period's elapsed time exceeds its own period end, announced added time or not.
    public var overtime: Bool
}

public enum ClockEngine {
    public static func format(_ seconds: Int) -> String {
        let s = max(0, seconds)
        return String(format: "%02d:%02d", s / 60, s % 60)
    }

    public static func display(match: Match, style: ClockStyle, now: Date) -> ClockDisplay {
        let elapsed = Int(match.clock.elapsed(at: now))
        guard let period = match.currentPeriod else {
            let shown = match.phase == .preMatch ? "00:00" : format(min(elapsed, lastPeriodEnd(for: match.phase)))
            return ClockDisplay(main: shown, added: nil, addedCounter: nil, state: match.phase.stateLabel, running: false, overtime: false)
        }
        let added = match.addedMinutes.map { "+\($0)" }
        let overtime = elapsed > period.endSeconds
        switch style {
        case .runOn:
            return ClockDisplay(main: format(elapsed), added: added, addedCounter: nil, state: nil, running: match.clock.running, overtime: overtime)
        case .freezeAndCount:
            let main = format(min(elapsed, period.endSeconds))
            let counter = (added != nil && overtime) ? format(elapsed - period.endSeconds) : nil
            return ClockDisplay(main: main, added: added, addedCounter: counter, state: nil, running: match.clock.running, overtime: overtime)
        }
    }

    private static func lastPeriodEnd(for phase: Phase) -> Int {
        switch phase {
        case .halfTime: return Period.firstHalf.endSeconds
        case .fullTime: return Period.secondHalf.endSeconds
        case .extraBreak: return Period.extraFirst.endSeconds
        case .extraFullTime, .shootout, .finished: return Period.extraSecond.endSeconds
        default: return 0
        }
    }
}
