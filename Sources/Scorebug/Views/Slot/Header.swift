import SwiftUI
import ScorebugCore

/// Fixed live controls between the preview and scrollable panels. The clock readout owns its own tick so
/// the enclosing bar stays equatable and goal/clock commands only update the values they affect.
struct LiveMatchBar: View, Equatable {
    let home: TeamEntry
    let away: TeamEntry
    let homeScore: Int
    let awayScore: Int
    let phase: Phase
    let clock: Clock
    let addedMinutes: Int?
    let clockStyle: ClockStyle?
    let aggregate: Aggregate?
    let slot: Int
    let model: AppModel
    let zoomGeneration: Int
    let promptGoalId: UUID?
    let addGoal: (Side) -> Void
    let dismissGoal: (UUID?) -> Void

    static func == (l: Self, r: Self) -> Bool {
        l.home == r.home && l.away == r.away && l.homeScore == r.homeScore && l.awayScore == r.awayScore
            && l.phase == r.phase && l.clock == r.clock && l.addedMinutes == r.addedMinutes
            && l.clockStyle == r.clockStyle && l.aggregate == r.aggregate && l.slot == r.slot && l.zoomGeneration == r.zoomGeneration
            && l.promptGoalId == r.promptGoalId
    }

    var body: some View {
        HStack(spacing: Space.sm) {
            teamColumn(.home, team: home, score: homeScore)
                .gridProbe("livebar-home", area: "livebar-columns", edge: nil)
            // Two rows: the clock with its phase, then Play beside the added-time controls. Rows only grow with
            // the phase (the pre-match hint), never with a tick, so nothing below jumps while the clock runs.
            VStack(spacing: Space.sm) {
                TimelineView(.periodic(from: .now, by: clock.running ? 1.0 : 3600)) { context in
                    ClockReadout(clock: clock, phase: phase, addedMinutes: addedMinutes,
                                 style: clockStyle ?? .runOn, tick: context.date, adjustAdded: adjustAdded) { playButton }
                        .layoutPriority(1)
                }
                if phase == .preMatch {
                    Text("Choose 1st in the Clock panel to kick off").scaledFont(.caption).foregroundStyle(.primary)
                }
            }
            .fixedSize(horizontal: true, vertical: false)
            .gridProbe("livebar-centre", area: "livebar-columns", edge: nil)
            teamColumn(.away, team: away, score: awayScore)
                .gridProbe("livebar-away", area: "livebar-columns", edge: nil)
        }
        .padding(.horizontal, Space.lg).padding(.vertical, Space.sm)
        .background(.bar)
        .gridArea("livebar-columns", inset: Space.lg)
    }

    /// The one prominent control in the bar (B17): the system bezel, green while running, with nothing painted on it.
    private var playButton: some View {
        let enabled = phase.period != nil
        let tint = clock.running ? Surface.statusSuccess : Color.accentColor
        return Button { model.apply(.playPause, slot: slot) } label: {
            Label(clock.running ? "Pause" : "Play", systemImage: clock.running ? "pause.fill" : "play.fill")
                .scaledFont(.body, weight: .semibold)
                .frame(minWidth: 80 * ScaledFonts.scale).scaledControl()
        }
        .buttonStyle(.borderedProminent).controlSize(.extraLarge).tint(tint)
        // Bare Space lives here, in the main window only, as before the menu commands; the menu uses ⇧⌘Space.
        .keyboardShortcut(.space, modifiers: [])
        .disabled(!enabled).help("Play or pause the clock (Space)")
        .gridProbe("livebar-button-play", area: "livebar-centre", edge: nil)
    }

    /// The engine's own step and cap (30, as the API and Stream Deck use), so the live bar is a shortcut, not a second rule.
    private func adjustAdded(_ delta: Int) { model.apply(.adjustAddedMinutes(delta), slot: slot) }

    private func teamColumn(_ side: Side, team: TeamEntry, score: Int) -> some View {
        // The design system's 44 pt minimum, scaled: big enough to hit live, small enough to keep the bar short.
        let goalButtonSide = 44 * ScaledFonts.scale
        return VStack(spacing: Space.sm) {
            HStack(spacing: Space.sm) {
                CrestView(team: team, size: 32, fitted: true)
                // The short name, shrunk before it truncates (N13); one line keeps both scores on one baseline.
                Text(team.shortName).scaledFont(.headline).lineLimit(1).minimumScaleFactor(0.6).help(team.name)
            }
            // Keep the normal compact score row when it fits; larger text moves the score above its controls.
            // Both alternatives keep intrinsic sizes, so ViewThatFits never compresses a clock or hit target.
            ViewThatFits(in: .horizontal) {
                HStack(spacing: Space.sm) {
                    scoreValue(side, team: team, score: score)
                    goalControls(side, team: team, score: score, buttonSide: goalButtonSide)
                }.fixedSize(horizontal: true, vertical: false)
                VStack(spacing: Space.sm) {
                    scoreValue(side, team: team, score: score)
                    goalControls(side, team: team, score: score, buttonSide: goalButtonSide)
                }.fixedSize(horizontal: true, vertical: false)
            }
        }
        .frame(maxWidth: .infinity)
        .gridArea("livebar-team-\(side == .home ? "home" : "away")", inset: 0)
    }

    private func scoreValue(_ side: Side, team: TeamEntry, score: Int) -> some View {
        let total = aggregate.map { score + (side == .home ? $0.firstLegHome : $0.firstLegAway) }
        return VStack(spacing: 0) {
            Text("\(score)").scaledFont(size: 56, weight: .bold, design: .rounded).monospacedDigit()
                .frame(minWidth: 64)
            if let total {
                Text("Agg \(total)").scaledFont(.caption).monospacedDigit().foregroundStyle(.primary)
                    .help("Aggregate score, including the first leg")
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(team.name) score")
        .accessibilityValue(total.map { "\(score), \($0) on aggregate" } ?? "\(score)")
    }

    private func goalControls(_ side: Side, team: TeamEntry, score: Int, buttonSide: CGFloat) -> some View {
        HStack(spacing: Space.sm) {
            Button { model.removeGoalFromWindow(.goal(side, -1), slot: slot) } label: {
                NudgeTile(symbol: "minus", side: buttonSide)
                    .gridProbe("livebar-button-goal-minus-\(side == .home ? "home" : "away")", area: "livebar-team-\(side == .home ? "home" : "away")", edge: nil)
            }
            .buttonStyle(.plain).disabled(score == 0).opacity(score == 0 ? Surface.disabledOpacity : 1)
            .accessibilityLabel("Remove last \(team.shortName) goal")
            .help(score == 0 ? "No \(team.shortName) goals to remove" : "Remove the last \(team.shortName) goal")
            PlusGoalButton(side: side, team: team, phase: phase, slot: slot, model: model,
                           buttonSide: buttonSide, promptGoalId: promptGoalId,
                           addGoal: { addGoal(side) }, dismissGoal: dismissGoal).equatable()
        }
    }

}

