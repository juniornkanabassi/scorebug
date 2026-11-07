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
            VStack(spacing: Space.md) {
                TimelineView(.periodic(from: .now, by: clock.running ? 1.0 : 3600)) { context in
                    ClockReadout(clock: clock, phase: phase, addedMinutes: addedMinutes,
                                 style: clockStyle ?? .runOn, tick: context.date, adjustAdded: adjustAdded)
                }
                Button { model.apply(.playPause, slot: slot) } label: {
                    Label(clock.running ? "Pause" : "Play", systemImage: clock.running ? "pause.fill" : "play.fill")
                        .frame(minWidth: 180).scaledControl(56)
                        .background(clock.running ? Surface.statusSuccess.opacity(0.35) : .clear, in: RoundedRectangle(cornerRadius: Radius.medium))
                }
                .buttonStyle(.borderedProminent).controlSize(.extraLarge).tint(clock.running ? Surface.statusSuccess : .accentColor)
                // Bare Space lives here, in the main window only, as before the menu commands; the menu uses ⇧⌘Space.
                .keyboardShortcut(.space, modifiers: [])
                .disabled(phase.period == nil).help("Play or pause the clock (Space)")
                if phase == .preMatch {
                    Text("Choose 1st to kick off").scaledFont(.caption).foregroundStyle(.secondary)
                }
            }
            .frame(minWidth: 180)
            teamColumn(.away, team: away, score: awayScore)
        }
        .padding(.horizontal, Space.lg).padding(.vertical, Space.sm)
        .background(.bar)
    }

    /// The same step and limits as the Added time panel, so the live bar is a shortcut, not a second rule.
    private func adjustAdded(_ delta: Int) {
        let clamped = max(0, min(15, (addedMinutes ?? 0) + delta))
        model.apply(.setAddedMinutes(clamped == 0 ? nil : clamped), slot: slot)
    }

    private func teamColumn(_ side: Side, team: TeamEntry, score: Int) -> some View {
        let goalButtonSide = max(44, 56) * ScaledFonts.scale
        return VStack(spacing: Space.sm) {
            HStack(spacing: Space.sm) {
                CrestView(team: team, size: 40, fitted: true)
                Text(team.shortName).scaledFont(.headline).lineLimit(1).help(team.name)
            }
            HStack(spacing: Space.sm) {
                let total = aggregate.map { score + (side == .home ? $0.firstLegHome : $0.firstLegAway) }
                VStack(spacing: 0) {
                    Text("\(score)").scaledFont(size: 56, weight: .bold, design: .rounded).monospacedDigit().frame(minWidth: 64)
                    if let total {
                        Text("Agg \(total)").scaledFont(.caption).monospacedDigit().foregroundStyle(.secondary)
                            .help("Aggregate score, including the first leg")
                    }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(team.name) score")
                .accessibilityValue(total.map { "\(score), \($0) on aggregate" } ?? "\(score)")
                Button { model.removeGoalFromWindow(.goal(side, -1), slot: slot) } label: {
                    Image(systemName: "minus").scaledFont(.title, weight: .bold).frame(width: goalButtonSide, height: goalButtonSide)
                        .frame(minWidth: goalButtonSide, minHeight: goalButtonSide)
                }
                .buttonStyle(.bordered).controlSize(.extraLarge).disabled(score == 0)
                .accessibilityLabel("Remove last \(team.shortName) goal")
                .help(score == 0 ? "No \(team.shortName) goals to remove" : "Remove the last \(team.shortName) goal")
                PlusGoalButton(side: side, team: team, phase: phase, slot: slot, model: model,
                               buttonSide: goalButtonSide, promptGoalId: promptGoalId,
                               addGoal: { addGoal(side) }, dismissGoal: dismissGoal).equatable()
            }
        }
        .frame(maxWidth: .infinity)
    }
}

